# Pairing 文件传输与图片上传（子项目 D）

日期：2026-08-02
状态：设计已确认，待实现
前置：子项目 C 已合入 main（`docs/superpowers/specs/2026-08-02-mobile-voice-input-design.md`）

## 背景

移动端 pairing 镜像的 Composer 面板（子项目 B）按钮行里留了一个 `Spacer()`，语音（C）与附件（D）各占其一。C 已落地，麦克风在右组。

手机上要把一张截图或照片交给桌面上的 agent CLI，今天唯一的办法是绕出 app：AirDrop、微信传输助手、或者把图上传到某个图床再把 URL 打进终端。D 让它变成一次点击：选图 → 字节经 pairing 通道到宿主 → 宿主写进那个终端面板的工作目录 → 绝对路径插进输入框。

## 目标

1. pairing 协议新增一条**分片文件传输 RPC**：`upload.begin` / 二进制分片帧 / `upload.commit`。
2. 宿主把字节写进被镜像面板的工作目录，**走该面板的 runtime target**（面板是 SSH 就 SFTP，是 WSL 就落进发行版）。
3. 宿主回**绝对路径**，手机原样插入 Composer，必要时 shell 引用。
4. Composer 新增 `+` 按钮，上传中显示确定进度。

### 非目标

- **拍照即传。** 只从相册选（`ImageSource.gallery`）。相机源要多一层选择表，且照片先落相册再选同样能用。
- **取消上传。** 需要额外的协议帧与宿主侧中断路径。上传中再点 `+` 无效。
- **并发上传。** 同时只允许一个。
- **非图片文件。** 扩展名白名单收在图片上。放开成任意文件会把这个原语从「往 cwd 放一张图」变成「任意文件写入」，风险不成比例。
- **实时 cwd。** 用面板启动时的 `workingDirectory`。用户 `cd` 到子目录后上传，文件落在启动目录 —— 但宿主回的是绝对路径，插进输入框照样能用，不会因为 `cd` 过而指错。读实时 cwd 要平台分支代码（Linux `/proc/<pid>/cwd`、macOS `lsof`），且 SSH 面板根本做不到，三种传输行为会不一致。
- **断点续传 / 校验和。** 传输走 TCP + WebSocket + 每帧认证加密，损坏几乎不可能；截断由「声明大小 vs 实际组装大小」抓住。再加 sha256 是白花钱。
- **桌面端 UI。** Composer 只存在于手机 pairing 镜像页。

## 协议

### 现状约束

`pairing_frames.dart` 的帧格式是 `[1 字节 kind][body]`，一帧等于一个 WebSocket 二进制消息。既有 kind：

```dart
enum PairingFrameKind { json, output, input, snapshot }
static const _kJson = 0x01;
static const _kOutput = 0x02;
static const _kInput = 0x03;
static const _kSnapshot = 0x04;
```

无应用层长度前缀、无分片、无请求/响应关联（关联 id 在 JSON 体内）。E2EE 是每帧一个 NaCl Box（`nonce(24) || ciphertext`）。**两端都没有任何大小上限**，手机→宿主方向零背压、零队列。

### 新增

帧种类加一个：

```dart
enum PairingFrameKind { json, output, input, snapshot, upload }
static const _kUpload = 0x05;

class UploadFrame extends PairingFrame {
  const UploadFrame(this.transferId, this.chunkIndex, this.bytes);
  final int transferId;
  final int chunkIndex;
  final Uint8List bytes;
}

static Uint8List encodeUpload(int transferId, int chunkIndex, Uint8List bytes);
```

线格式 `[0x05][varint transferId][varint chunkIndex][raw bytes]`，与既有 `_encodeSeqFrame` 同构。

**为什么二进制而非 base64 JSON**：base64 有 33% 膨胀，且每片一次 `jsonEncode`/`jsonDecode`，在手机上白烧 CPU 与内存。需要应答的只有首尾两个 RPC，正好复用既有的 JSON `id` 关联机制。

### RPC

| 方法 | 参数 | 回复 |
|---|---|---|
| `upload.begin` | `{sub, filename, size}` | `{transferId, chunkSize}` 或 error |
| `upload.commit` | `{transferId}` | `{path}` 或 error |
| `upload.ack`（宿主→手机，JSON 事件，无 id） | `{transferId, received}` | — |

`chunkSize` 由宿主在 `begin` 回复里给出（**64 KiB**），手机照它切。宿主定分片大小意味着以后调整不需要改手机端。

错误码（JSON-RPC error 的 `code` 字段用字符串常量，与既有风格一致）：`too_large`、`unsupported_type`、`bad_filename`、`no_target`、`write_failed`、`unknown_transfer`。

`no_target` 有两个来源：`sub` 未订阅（handler 判），以及该 workspace 解析不出可写的 runtime target（sink 判）。两者对用户是同一件事 —— 这次上传没有落点。

### 类型

```dart
/// upload.begin 的结果。失败时 code 是上表的错误码之一。
class UploadBeginResult {
  const UploadBeginResult.ok(this.transferId, this.chunkSize) : code = null;
  const UploadBeginResult.error(this.code) : transferId = 0, chunkSize = 0;
  final int transferId;
  final int chunkSize;
  final String? code;
  bool get isOk => code == null;
}

/// chunk 只会成功或作废整个 transfer，没有中间态。
class UploadChunkResult {
  const UploadChunkResult.ok(this.received) : code = null;
  const UploadChunkResult.error(this.code) : received = 0;
  final int received;         // 该 transfer 累计已收字节
  final String? code;
  bool get isOk => code == null;
}

class UploadCommitResult {
  const UploadCommitResult.ok(this.path) : code = null;
  const UploadCommitResult.error(this.code) : path = '';
  final String path;          // 宿主上的绝对路径
  final String? code;
  bool get isOk => code == null;
}

/// 宿主推来的信用窗口回执。
class PairingUploadAck {
  const PairingUploadAck({required this.transferId, required this.received});
  final int transferId;
  final int received;
}
```

### 流控 —— 本协议第一个

手机→宿主今天零背压，`_socket.add` 无界缓冲。80 片背靠背发出去，25MB 会在手机上堆成真实内存尖峰。

信用窗口：**每 16 片（1 MiB）等一次 `upload.ack`**。在途量因此钉在 1 MiB，每 MiB 一个 RTT —— 局域网上可忽略，同时白送真实进度数据给 UI。`ack` 是无 id 的 JSON 事件而非 RPC 回复，因为它是宿主主动推的，与既有 `session.changed` / `terminal.closed` 同类。

### 分片序号

WebSocket 保序，所以序号不是为了重排。它的作用是让宿主发现空洞时**中断而不是默默写出一个残缺文件**：收到的 `chunkIndex` 必须等于期望的下一个，否则整个 transfer 作废并回 `write_failed`。

### 大小上限

**25 MB**，宿主在 `upload.begin` 就按声明的 `size` 拒（`too_large`），流式过程中累计收超同样中断。手机照片 2–8MB、截图 200KB–2MB，25MB 足够宽松，又小到一个有 bug 的客户端打不倒桌面。手机侧也先自查一遍，好在选图后立刻给出提示而不是等一次往返。

## 安全

这个功能给 pairing 协议新增了一个**磁盘写入原语**。此前一台配对的手机只能写 PTY 输入；之后它能让宿主往文件系统写字节。以下每条都是必需的，不是加固。

**文件名一律拒绝，不做静默清洗。** 宿主拒收含 `/`、`\`、空字节的名字，等于 `.` 或 `..` 的名字，以及空名字，回 `bad_filename`。**反斜杠也要拒** —— 只在 posix 上下文里 `basename` 剥不掉 `..\..\x`。选择拒绝而非清洗：手机若发来带路径成分的名字，那是 bug 或恶意，静默改写会把这件事藏起来。

**扩展名白名单** `{png, jpg, jpeg, webp, gif, heic}`，大小写不敏感。**heic 必须在内** —— iPhone 默认拍 HEIC，`image_picker` 的转换行为跨版本不可靠，漏掉它会在 iOS 上随机失败。不在白名单回 `unsupported_type`。

**重名不覆盖。** 目标路径已存在时在扩展名前追加 `-1`、`-2`……直到空位，宿主回实际路径。这条规则顺带堵住一个洞：cwd 里预先埋一个名叫 `photo.jpg` 的符号链接指向 `/etc/passwd`，因为我们从不往已存在的路径写，实际会写成 `photo-1.jpg`。**防覆盖与防符号链接是同一条规则** —— 谁改动这里都要知道这一点。

**上限 100 次重名尝试**后放弃回 `write_failed`，免得攻击者用大量同名文件把宿主拖在循环里。

## 架构

### 宿主端分层

`PairingRpcHandler` 今天完全不认识存储层，这一点要保住。

```dart
/// Assembles chunks, validates, and hands finished bytes to the sink.
/// Knows the protocol; knows nothing about filesystems.
class PairingUploadReceiver {
  PairingUploadReceiver({
    required PairingUploadSink sink,
    int maxBytes = 25 * 1024 * 1024,
    int chunkSize = 64 * 1024,
  });

  UploadBeginResult begin({
    required String workspaceId,
    required String cwd,
    required String filename,
    required int size,
  });
  UploadChunkResult chunk(int transferId, int chunkIndex, List<int> bytes);
  Future<UploadCommitResult> commit(int transferId);
  void abandon(int transferId);
  void abandonAll();          // connection closed
}

/// Resolves the pane's runtime target to a filesystem and writes.
/// Wired in bootstrap, where the catalog and SessionLifecycleService both live.
typedef PairingUploadSink = Future<String> Function({
  required String workspaceId,
  required String cwd,
  required String filename,
  required List<int> bytes,
});
```

职责切分：receiver 管协议与校验（分片连续性、大小、文件名、扩展名），sink 只管「解析文件系统 → 挑不冲突的路径 → `writeBytes` → 回绝对路径」。重名探测需要文件系统，所以在 sink 里。

handler 的测试塞假 sink，一行存储代码都不用碰。

**`workspaceId` 与 `cwd` 由 handler 提供给 receiver**，receiver 自己不认识订阅表：`upload.begin` 的 `sub` → `_subs[sub]` 拿到 `_Subscription{catalogId, session}` → `cwd` 取 `session.runtimeTarget.workingDirectory`，`workspaceId` 取 `_catalog.resolve(catalogId)` 得到的条目上的 `workspaceId`。`sub` 未订阅时 handler 直接回 `no_target`，不进 receiver。

### 那条链

`app_shell.dart` 里把 sink 接成：

```
workspaceId
  → sessionRepo.loadWorkspacesIndex() / workspace folders
  → folders.first.targetId
  → sessionLifecycleService.resolveWorkContextForTargetId(targetId)
  → RuntimeContext.filesystem
  → ensureDir(cwd) → 挑不冲突路径 → writeBytes
```

**这是 D 里最大一块隐形工作量。** 整个 pairing 栈此前只碰 `TerminalSession` 的 PTY I/O，没有任何现成 helper 从 pairing 帧走到 `RuntimeContext`。

注意仓里有**两个** `RuntimeTarget` 类型，实现时不能混：

| 类型 | 用途 |
|---|---|
| `services/workspace_dnd/runtime_target.dart` | 会话身上那个，带 `workingDirectory`（即 cwd），**不连文件系统** |
| `models/runtime_target.dart` | 存储/执行目标（`id`、`kind` local/wsl/ssh），能解析成 `RuntimeContext` |

cwd 来自前者（`session.runtimeTarget.workingDirectory`），文件系统来自后者。

写入用 `Filesystem.writeBytes(String path, List<int> bytes)`（`services/io/filesystem.dart:74`），三种后端都实现了；路径拼接用该后端的 `pathContext`，不要硬编码 `/`。

### 手机端分层

```dart
/// Chunked send with a credit window. Injected callbacks, no socket.
class PairingUploadSender {
  PairingUploadSender({
    required Future<Map<String, Object?>> Function(String method, Map<String, Object?> params) rpc,
    required void Function(Uint8List frame) send,
    required Stream<PairingUploadAck> acks,
    int windowChunks = 16,
  });

  Future<String> upload({
    required int sub,
    required String filename,
    required Uint8List bytes,
    void Function(int sent, int total)? onProgress,
  });
}
```

`acks` 从哪来：`PairingClient._onJson` 今天已按 `method` 路由 `auth.ok` / `terminal.closed` / `session.changed` 等无 id 事件。新增 `upload.ack` 分支，解析成 `PairingUploadAck` 推进一个 broadcast `StreamController`，`PairingClient` 以 `Stream<PairingUploadAck> get uploadAcks` 暴露给 sender。

`PairingClient` 新增 `uploadFile({required int sub, required String filename, required Uint8List bytes, void Function(int, int)? onProgress})` 转发给 sender。`PairingClientCubit` 再加一个薄转发，从 `_activeSubscription` 取 `sub`（与既有 `sendInput`/`sendResize` 同一写法），这样 `ImageUploadCubit` 注入的 `upload` 函数签名里不带 `sub` —— 镜像页不需要知道订阅 id。

### 状态归属

`ImageUploadCubit` 由**镜像页创建**（和它已经在本地创建 `MobileToolbarCubit` 一样），不进 pairing shell。理由：上传只在镜像期间有意义，状态本就该随镜像页销毁；而语音的 provider 选择与凭据是跨屏偏好，才需要活在 shell 层。

```dart
enum ImageUploadStatus { idle, picking, uploading }

enum ImageUploadFailure { tooLarge, unsupportedType, failed }

/// What the injected picker returns. Keeps image_picker's XFile out of the
/// cubit so its tests need neither the plugin nor a photo library.
class PickedImage {
  const PickedImage({required this.filename, required this.bytes});
  final String filename;
  final Uint8List bytes;
}

class ImageUploadState {
  final ImageUploadStatus status;
  final int sentBytes;
  final int totalBytes;
  double get progress => totalBytes == 0 ? 0 : sentBytes / totalBytes;
}

class ImageUploadCubit extends Cubit<ImageUploadState> {
  ImageUploadCubit({
    required Future<PickedImage?> Function() pickImage,
    required Future<String> Function({
      required String filename,
      required Uint8List bytes,
      void Function(int sent, int total)? onProgress,
    }) upload,
    int maxBytes = 25 * 1024 * 1024,
  });

  Stream<String> get paths;                    // 宿主回的绝对路径
  Stream<ImageUploadFailure> get failures;
  Future<void> pickAndUpload();
}
```

进度进 state（UI 必须重画，且每 1 MiB 一次 emit，全程最多 ~25 次）；**路径与失败走 broadcast 流** —— 两者都是一次性事件，路径要写进别人持有的 `TextEditingController`，失败要弹 snackbar 且可能在面板已卸载后才到。与 C 期 `VoiceInputCubit` 的 `transcripts` / `failures` 完全同构。

`pickImage` 与 `upload` 都是注入的函数，所以 cubit 测试既不开相册也不开 socket。

### 文件

| 文件 | 职责 |
|---|---|
| `lib/services/pairing/pairing_frames.dart`（改，+~30 行） | `upload` kind、`UploadFrame`、`encodeUpload`、`decode` 分支 |
| `lib/services/pairing/pairing_upload_receiver.dart`（新建，~180 行） | 宿主侧组装与校验，零存储依赖 |
| `lib/services/pairing/pairing_upload_sender.dart`（新建，~120 行） | 手机侧分片与信用窗口，零 socket 依赖 |
| `lib/services/pairing/pairing_rpc_handler.dart`（改，+~60 行） | 三个方法 + `UploadFrame` 分支 + `abandonAll` on close |
| `lib/services/pairing/pairing_client.dart`（改，+~40 行） | `uploadFile`、ack 事件路由 |
| `lib/utils/shell_quote.dart`（新建，~30 行） | 纯函数 `shellQuotePath` |
| `lib/cubits/image_upload_cubit.dart`（新建，~180 行） | 选图 + 上传编排 |
| `lib/pages/pairing/mobile_toolbar/mobile_composer_panel.dart`（改，+~50 行） | `+` 按钮两态 |
| `lib/pages/pairing/mobile_toolbar/upload_failure_messenger.dart`（新建，~50 行） | 失败流 → snackbar |
| `lib/pages/pairing/pairing_mirror_page.dart`（改，+~25 行） | 创建 cubit、订阅 `paths` |
| `lib/app/app_shell.dart`（改，+~40 行） | 接 `PairingUploadSink` |
| `lib/utils/ui/app_keys.dart`（改） | `mobileComposerAttachButton` |
| `lib/l10n/app_en.arb` / `app_zh.arb`（改） | 4 条文案 |

## UI

`+` 按钮进**左组**，submit 切换之后、`Spacer()` 之前，用现成的私有 `_CircleButton`（`TpIconButton`，`size: 34`、`iconSize: 18`、`borderRadius: 17`），与左侧三个同款。

| 状态 | 表现 |
|---|---|
| `idle` | `Icons.add` |
| `picking` | `Icons.add`，`onTap: null`（相册表已经盖住屏幕，不需要额外指示） |
| `uploading` | 同尺寸圆片里放 **确定进度** `CircularProgressIndicator(value: state.progress, strokeWidth: 2)`，`onTap: null` |

仓里 pairing 下所有进度都是不确定转圈（`pairing_node_row.dart:85`、麦克风的 `starting` 态、连接测试）。这里用确定进度是**有意的偏离**：我们真的知道字节数，有确定进度却显示不确定转圈是在丢信息。

成功后把宿主回的绝对路径经 `insertTranscript(TextEditingValue, String)`（`services/stt/transcript_insertion.dart:14`，C 期的纯函数，与语音无耦合）插进输入框，末尾补一个空格。

### shell 引用

插入前过 `shellQuotePath`：路径只含 `[A-Za-z0-9._/-]` 时原样返回，否则套单引号并把内嵌单引号转成 `'\''`。cwd 带空格时 `cat /Users/me/My Project/photo.jpg` 会断成两个参数 —— 插进去就不能用，等于这个功能在带空格的路径下失效。

## 错误处理

| 情形 | 响应 |
|---|---|
| 选图取消 | 状态回 `idle`，无提示 |
| 手机侧自查超 25 MB | snackbar `imageUploadTooLarge`，不发 `begin`（省一次往返） |
| 宿主回 `too_large` | snackbar `imageUploadTooLarge` |
| 宿主回 `unsupported_type` | snackbar `imageUploadUnsupportedType` |
| 其他错误码 / 传输中断 / RPC 超时 | snackbar `imageUploadFailed` + `AppLogger.instance.w` 记细节 |
| 上传中离开镜像页 | cubit 随页销毁；宿主侧连接关闭时 `abandonAll()` 丢弃未完成的 transfer |

snackbar 照仓内惯例：`ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.key)))`。

宿主侧未完成的 transfer 必须在连接关闭时清掉，否则一个反复断连的手机能把桌面内存喂满 —— 每个未完成 transfer 都持着已收的字节。

## 已知副作用

- 上传期间图片字节在手机与宿主内存各有一份（上限 25 MB）；宿主在 `commit` 写盘后立即释放。
- 文件写进面板工作目录，会出现在 `git status` 的未跟踪列表里。这是「图片落在代码旁边」的直接代价，用户选的就是这个。
- 面板启动在子目录时，文件落在那个子目录而非仓库根。
- Composer 按钮行左组从三个变四个，加上右组的麦克风与发送共六个 34px 控件。在 320pt 宽的设备上会挤 —— 实现时需实测，必要时收紧间距（A 期有过第三个按钮把控件挤出测试画布的先例）。

## 测试

不碰真 socket、不碰真相册、不碰真文件系统。全部构造函数注入。

### 纯函数 golden test

- `shell_quote_test.dart`：纯字母数字路径原样返回；带空格套单引号；内嵌单引号转 `'\''`；带 `$`、反引号、`&`、换行的路径；空字符串。
- `pairing_frames_test.dart`（追加）：`encodeUpload` 头字节 `0x05`、varint `transferId` 与 `chunkIndex`、raw 尾部；`decode` 往返；**既有四种 kind 的编解码不受影响**（回归钉）；截断帧抛错。

### `PairingUploadReceiver`（假 sink）

`begin` 拒绝超限大小、拒绝白名单外扩展名（含大写变体）、拒绝含 `/`、含 `\`、`.`、`..`、空的文件名；`chunk` 在序号出现空洞时作废 transfer；累计收超声明大小时中断；`commit` 在实际组装大小 ≠ 声明大小时回 `write_failed`；`commit` 未知 `transferId` 回 `unknown_transfer`；`abandonAll` 清空并释放字节；`heic` 被接受。

### `PairingUploadSender`（假 rpc + 假 send + 假 ack 流）

`begin` → 分片顺序与序号正确 → `commit` 返回宿主给的路径；**在途分片数不超过窗口**（发满 16 片后在收到 ack 前不再发，这条是流控的核心，要能失败）；`begin` 报错时**一片都不发**；分片中途 rpc 抛错时中止且不 `commit`；`onProgress` 单调递增且末值等于总字节数；按宿主回的 `chunkSize` 切而非硬编码。

### `PairingRpcHandler`（追加，假 receiver）

`upload.begin`/`upload.commit` 路由正确；`UploadFrame` 交给 receiver；连接关闭调 `abandonAll`；未订阅的 `sub` 回 `no_target`。

### `ImageUploadCubit`（假 picker + 假 upload）

选图取消 → 回 `idle` 且不上传；成功 → `paths` 收到宿主路径；手机侧超限 → `failures` 收到 `tooLarge` 且不调 upload；upload 抛错 → `failures` 且状态回 `idle`；`progress` 随回调推进；上传中再调 `pickAndUpload` 无效；`close()` 关闭两个流控制器。

### widget

`+` 按钮存在且可点；`uploading` 态显示确定进度且不可点；成功后路径出现在输入框且带 shell 引用；失败弹 snackbar。

`bloc_test` 不加（非本仓依赖），`fake_async` 已有。期望抛出必须钉类型，不写 `throwsA(anything)`，不写恒真断言。

### 一条必须正面改的既有测试

`client/test/pages/pairing/mobile_composer_panel_test.dart` 的 `renders the field and its four controls` 断言精确控件数量。面板确实合法地多了一个控件，所以**改这条测试的名字与数量是正确的，不是削弱** —— C 期「不许改既有断言」那条规矩针对的是为了让新代码过关而放宽既有契约，不是禁止在契约本身改变时同步更新它。实现时要显式改，并在提交信息里说明原因。

## l10n

`app_en.arb` / `app_zh.arb` 各加 4 条。仅 `imageUploadTooLarge` 带 `@` placeholder 块（只进模板文件 `app_en.arb`）。

| key | en | zh |
|---|---|---|
| `mobileComposerAttach` | Attach image | 附加图片 |
| `imageUploadFailed` | Image upload failed | 图片上传失败 |
| `imageUploadTooLarge` | Image is larger than {mb} MB | 图片超过 {mb} MB |
| `imageUploadUnsupportedType` | That image type is not supported | 不支持该图片格式 |

改完跑 `dart run tool/gen_warmup_glyphs.dart`；生成的 `AppLocalizations` 若落后于 ARB，跑 `flutter gen-l10n`（A、B、C 期各遇一次，共三次）。

## 真机验证清单

自动化覆盖不到，但每条都能一眼看出坏没坏。

1. 本机面板：选一张相册图 → 进度走满 → 输入框出现绝对路径 → 终端里 `ls` 能看到该文件。
2. SSH 面板：同上，文件出现在**远程主机**的 cwd 而非桌面本机。
3. WSL 面板：文件出现在发行版内的 cwd。
4. iPhone 拍的 HEIC 图：不被拒。
5. cwd 带空格的工作区：插入的路径带引号，直接回车可用。
6. 同名上传两次：第二次落成 `-1` 后缀，输入框里是实际路径。
7. 超过 25 MB 的图（录屏截帧或原图）：立刻提示，不发起传输。
8. 上传进行中退出镜像页：桌面无残留临时文件，再次进入可正常上传。
