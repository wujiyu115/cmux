# Pairing 文件传输与图片上传 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 手机在 pairing 镜像的 Composer 里点 `+` 选一张图，字节经 pairing 通道分片传到桌面宿主，宿主把它写进被镜像终端面板的工作目录（走该面板的 runtime target），回绝对路径插进输入框。

**Architecture:** pairing 协议新增二进制帧 kind `0x05` 承载分片，首尾用既有 JSON-RPC 机制做 `upload.begin` / `upload.commit`；宿主侧分两层 —— `PairingUploadReceiver` 管协议与校验（零存储依赖），注入的 `PairingUploadSink` 管「解析该面板的 runtime target → 挑不冲突路径 → 写字节」，真正的解析留在 bootstrap。手机侧 `PairingUploadSender` 管分片与信用窗口（零 socket 依赖），`ImageUploadCubit` 管选图与编排。帧编解码与 shell 引用抽成纯函数做 golden test。

**Tech Stack:** Flutter / `flutter_bloc` / `image_picker ^1.1.2`（已有）/ `pinenacl`（既有 E2EE）/ `path`

Spec：`docs/superpowers/specs/2026-08-02-pairing-file-transfer-design.md`

## 对 spec 的一处更正

**spec 说错误码走「JSON-RPC error 的 `code` 字段」。该字段不存在。** 实际 `PairingRpcHandler._replyError(Object? id, String message)`（`pairing_rpc_handler.dart:305`）发的是 `{'id': id, 'error': <字符串>}`，而客户端 `_onJson` 收到后一律 `pending.completeError(Exception(data['error'].toString()))` —— 结构化的码到不了对面，只剩一个要靠字符串嗅探的 `Exception`。

**本计划改为：上传的三个 RPC 把成败放在 `result` 信封里，从不使用 `error` 字段。**

```
upload.begin  → result: {'ok': true, 'transferId': int, 'chunkSize': int}
                     或 {'ok': false, 'code': 'too_large'}
upload.commit → result: {'ok': true, 'path': String}
                     或 {'ok': false, 'code': 'write_failed'}
```

这样错误码结构化地过河，且 `_replyError` 与客户端的错误管线一行都不用改。代价是这两个方法不走 JSON-RPC 的标准错误通道 —— 在注释里写明原因，别让下一个人「修正」回去。

`error` 字段仍保留给真正的协议级失败（未知方法等），由既有代码产生。

## Global Constraints

- 工作目录 `client/`。完成前必跑 `flutter analyze --no-fatal-infos --no-fatal-warnings` 与 `flutter test --exclude-tags integration`。
- **绝不 `git add -A` 或 `git add .`**。仓内有一批与本项目无关的未提交文件（`client/ios/Flutter/*.xcconfig`、`client/ios/Runner.xcodeproj/project.pbxproj`、`client/ios/Runner.xcworkspace/contents.xcworkspacedata`、`client/ios/Podfile`、`client/ios/Podfile.lock`，以及 submodule 指针 `client/packages/flutter_alacritty`）。每次提交显式列出本任务的文件。
- **两个既存失败的测试文件不准碰、不准"修"**：`client/test/pages/command_palette/command_palette_overlay_test.dart`、`client/test/services/terminal/pty_launch_environment_test.dart`。它们在 main 上就是失败的。
- 状态管理只用 `flutter_bloc`，不用 `provider`，共享状态不用 `setState`（单个 widget 自己的动画/本地开关可以）。
- **`bloc_test` 不是本仓依赖，不准加**。`fake_async` 已有。
- 所有用户可见文案必须 l10n：`lib/l10n/app_en.arb` 与 `lib/l10n/app_zh.arb` **两个都要加**，经 `context.l10n.<key>` 使用。改完跑 `dart run tool/gen_warmup_glyphs.dart`；生成的 `AppLocalizations` 若落后于 ARB，跑 `flutter gen-l10n`（A、B、C 期各遇一次）。
- 不准用 `print`。诊断日志用 `AppLogger.instance.w(msg, error: e, stackTrace: st)`（`lib/utils/logging/logger_utils.dart`）。
- **不加新依赖。** `image_picker: ^1.1.2` 已在 pubspec 且已被 `pairing_scan_page.dart` 使用。
- 测试中的 socket / 文件系统 / 相册一律构造函数注入，禁止真实 IO。
- 期望抛出必须钉类型（`throwsA(isA<TimeoutException>())`），**不准写 `throwsA(anything)`**，不准写恒真断言（`expect(x, isA<int>())` 当 `x` 静态就是 `int` 时；`expect(stopwatchMs, greaterThanOrEqualTo(0))`）。
- 渲染本地化 UI 的 widget test 必须给 `MaterialApp` 传 `localizationsDelegates: AppLocalizations.localizationsDelegates`、`supportedLocales: AppLocalizations.supportedLocales`、`locale: const Locale('en')`。
- 文件大小软上限：page shell ~400 行、cubit ~500、service ~600。`build()` 里不做 IO。
- **上限 25 MB**（`25 * 1024 * 1024`），**分片 64 KiB**（`64 * 1024`），**信用窗口 16 片**。三个数都做构造参数，生产默认取这些值，测试注入小值。
- 扩展名白名单恰为 `{png, jpg, jpeg, webp, gif, heic}`，大小写不敏感。**heic 必须在内** —— iPhone 默认拍 HEIC。
- 文件名**拒绝而非清洗**：含 `/`、`\`、空字节，或等于 `.`/`..`，或为空，一律回 `bad_filename`。
- **重名不覆盖**，扩展名前追加 `-1`、`-2`…，最多试 100 次。这条同时是防符号链接的机制（cwd 里埋一个指向 `/etc/passwd` 的 `photo.jpg` 时，我们写 `photo-1.jpg`），改动此处必须知道。
- 路径拼接一律用后端的 `Filesystem.pathContext`，不准硬编码 `/`。

---

## File Structure

| 文件 | 职责 | 任务 |
|---|---|---|
| `lib/services/pairing/pairing_frames.dart`（改） | `upload` kind、`UploadFrame`、`encodeUpload`、`decode` 分支 | 1 |
| `lib/utils/shell_quote.dart`（新建） | 纯函数 `shellQuotePath` | 2 |
| `lib/services/pairing/pairing_upload_receiver.dart`（新建） | 宿主侧组装与校验；`PairingUploadSink` typedef；四个结果类型 | 3 |
| `lib/services/pairing/pairing_upload_sender.dart`（新建） | 手机侧分片与信用窗口；`PairingUploadAck` | 4 |
| `lib/services/pairing/pairing_rpc_handler.dart`（改） | 三个方法 + `UploadFrame` 分支 + `dispose` 里 `abandonAll` + 发 `upload.ack` | 5 |
| `lib/services/pairing/pairing_connection.dart`（改） | 把 sink 穿到 handler | 5 |
| `lib/services/pairing/lan_pairing_server.dart`（改） | 把 sink 穿到 connection | 5 |
| `lib/app/app_shell.dart`（改） | 实现 `PairingUploadSink` | 5 |
| `lib/services/pairing/pairing_client.dart`（改） | `uploadFile`、`uploadAcks` 流、`upload.ack` 路由 | 6 |
| `lib/cubits/pairing_client_cubit.dart`（改） | `uploadImage` 薄转发 | 6 |
| `lib/cubits/image_upload_cubit.dart`（新建） | 选图 + 上传编排；`PickedImage`、`ImageUploadFailure` | 7 |
| `lib/pages/pairing/mobile_toolbar/mobile_composer_panel.dart`（改） | `+` 按钮两态 | 8 |
| `lib/pages/pairing/mobile_toolbar/upload_failure_messenger.dart`（新建） | 失败流 → snackbar | 8 |
| `lib/pages/pairing/pairing_mirror_page.dart`（改） | 创建 cubit、订阅 `paths` | 8 |
| `lib/utils/ui/app_keys.dart`（改） | `mobileComposerAttachButton` | 8 |
| `lib/l10n/app_en.arb` / `app_zh.arb`（改） | 4 条文案 | 8 |

任务依赖：1 → 3、4；3 → 5；4 → 6；6 → 7；2、7 → 8。

**Task 5 刻意把 handler、connection、server、bootstrap 四处并成一个任务。** sink 是 handler 的必需构造参数，要一路穿到 `LanPairingServer` 才能由 bootstrap 提供 —— 拆开会留下一个「协议已认识 upload 但没有落点」的中间态，那种状态既不可测也不可审。

---

### Task 1: upload 帧

**Files:**
- Modify: `client/lib/services/pairing/pairing_frames.dart`
- Modify: `client/lib/services/pairing/pairing_rpc_handler.dart`（只加一个防御 `case`）
- Modify: `client/lib/services/pairing/pairing_client.dart`（只加一个防御 `case`）
- Test: `client/test/services/pairing/pairing_frames_test.dart`（若不存在则新建）

**Interfaces:**
- Consumes: 无。
- Produces:
  - `PairingFrameKind` 新增枚举值 `upload`
  - `class UploadFrame extends PairingFrame { const UploadFrame(int transferId, int chunkIndex, Uint8List bytes); final int transferId; final int chunkIndex; final Uint8List bytes; }`
  - `static Uint8List PairingCodec.encodeUpload(int transferId, int chunkIndex, Uint8List bytes)`
  - `PairingCodec.decode` 认 `0x05` 并返回 `UploadFrame`

**现状（读过再动）：** 帧是 `[1 字节 kind][body]`，既有 kind 常量 `_kJson = 0x01`、`_kOutput = 0x02`、`_kInput = 0x03`、`_kSnapshot = 0x04`。`_Writer` 提供 `byte`/`varint`（LEB128，负数抛 `ArgumentError`）/`raw`/`take`，`_Reader` 提供 `byte`/`varint`/`rest`。`decode` 是一个 `switch (kind)`，`default` 抛 `FormatException`。

**`PairingFrame` 是 `sealed`**，所以新增子类会让 `pairing_rpc_handler.dart:61` 的 `handle` 与 `pairing_client.dart:301` 的 `_onBytes` 两处 `switch (frame)` 的穷举检查失效。**本任务必须同时补上这两处的防御分支**，让每一个提交都能编译、能 bisect、能跑 CI：

```dart
      // pairing_rpc_handler.dart — handle(), beside the existing
      // OutputFrame()/SnapshotFrame() defensive cases.
      // Task 5 replaces this with real chunk handling.
      case UploadFrame():
        break;
```

```dart
      // pairing_client.dart — _onBytes(). This one stays a permanent no-op:
      // the phone sends upload frames and never receives them.
      case UploadFrame():
        break;
```

所以本任务的验证**要跑全量 analyze**，不留编译不过的中间态。

- [ ] **Step 1: 写失败的测试**

`client/test/services/pairing/pairing_frames_test.dart`：

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/pairing/pairing_frames.dart';

void main() {
  group('encodeUpload', () {
    test('writes the kind byte, both varints, then the raw payload', () {
      final frame = PairingCodec.encodeUpload(
        7,
        3,
        Uint8List.fromList(const [1, 2, 3]),
      );
      expect(frame[0], 0x05, reason: 'upload kind');
      expect(frame[1], 7, reason: 'transferId as a single-byte varint');
      expect(frame[2], 3, reason: 'chunkIndex as a single-byte varint');
      expect(frame.sublist(3), const [1, 2, 3], reason: 'payload is not framed');
    });

    test('encodes multi-byte varints', () {
      // 300 needs two LEB128 bytes; a transfer id or chunk index above 127 must
      // not be truncated to one byte.
      final frame = PairingCodec.encodeUpload(300, 200, Uint8List(0));
      final decoded = PairingCodec.decode(frame) as UploadFrame;
      expect(decoded.transferId, 300);
      expect(decoded.chunkIndex, 200);
    });

    test('carries an empty payload', () {
      final decoded =
          PairingCodec.decode(PairingCodec.encodeUpload(1, 0, Uint8List(0)))
              as UploadFrame;
      expect(decoded.bytes, isEmpty);
    });
  });

  group('decode', () {
    test('round-trips an upload frame', () {
      final payload = Uint8List.fromList(List.generate(256, (i) => i));
      final decoded = PairingCodec.decode(
        PairingCodec.encodeUpload(42, 9, payload),
      );
      expect(decoded, isA<UploadFrame>());
      final upload = decoded as UploadFrame;
      expect(upload.transferId, 42);
      expect(upload.chunkIndex, 9);
      expect(upload.bytes, payload);
    });

    test('still round-trips every pre-existing kind', () {
      // Regression guard: adding a fifth kind must not shift any other kind's
      // layout. These four carry the terminal hot path.
      final json = PairingCodec.decode(
        PairingCodec.encodeJson({'method': 'ping'}),
      );
      expect((json as JsonFrame).data['method'], 'ping');

      final bytes = Uint8List.fromList(utf8.encode('ls -la'));
      final output = PairingCodec.decode(PairingCodec.encodeOutput(1, 2, bytes));
      expect((output as OutputFrame).sub, 1);
      expect(output.seq, 2);
      expect(output.bytes, bytes);

      final snapshot = PairingCodec.decode(
        PairingCodec.encodeSnapshot(3, 4, bytes),
      );
      expect((snapshot as SnapshotFrame).sub, 3);
      expect(snapshot.seq, 4);

      final input = PairingCodec.decode(PairingCodec.encodeInput(5, bytes));
      expect((input as InputFrame).sub, 5);
      expect(input.bytes, bytes);
    });

    test('throws FormatException on an unknown kind', () {
      expect(
        () => PairingCodec.decode(Uint8List.fromList(const [0x7f])),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when an upload frame is truncated', () {
      // Kind byte present but the transferId varint is missing.
      expect(
        () => PairingCodec.decode(Uint8List.fromList(const [0x05])),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd client && flutter test test/services/pairing/pairing_frames_test.dart
```

预期：编译失败，`Method not found: 'encodeUpload'` 或 `Undefined name 'UploadFrame'`。

- [ ] **Step 3: 改 `pairing_frames.dart`**

四处改动：

1. 文件头的枚举加一个值：

```dart
enum PairingFrameKind { json, output, input, snapshot, upload }
```

2. 文件头的文档注释补一段（现有注释列举了 json 与「binary terminal」两类，upload 属于第三类）：

```dart
/// - **Binary upload** (`0x05`) — phone→host file chunks with a varint
///   `transferId` and `chunkIndex`. Bookended by `upload.begin` /
///   `upload.commit` JSON-RPC; the chunks themselves stay binary so a photo
///   does not pay base64's 33% inflation.
```

3. 新增帧类，放在 `InputFrame` 之后：

```dart
class UploadFrame extends PairingFrame {
  const UploadFrame(this.transferId, this.chunkIndex, this.bytes);
  final int transferId;
  final int chunkIndex;
  final Uint8List bytes;
}
```

4. `PairingCodec` 里加常量、编码器、解码分支：

```dart
  static const _kUpload = 0x05;

  static Uint8List encodeUpload(int transferId, int chunkIndex, Uint8List bytes) {
    final builder = _Writer()
      ..byte(_kUpload)
      ..varint(transferId)
      ..varint(chunkIndex)
      ..raw(bytes);
    return builder.take();
  }
```

`decode` 的 `switch` 里，`case _kInput` 之后加：

```dart
      case _kUpload:
        final transferId = reader.varint();
        final chunkIndex = reader.varint();
        return UploadFrame(transferId, chunkIndex, reader.rest());
```

**不要**复用 `_encodeSeqFrame` —— 它的两个 varint 语义是 `sub`/`seq`，与 `transferId`/`chunkIndex` 无关，共用会让两种帧的含义纠缠在一个私有函数里。

- [ ] **Step 4: 跑测试确认通过**

```bash
cd client && flutter test test/services/pairing/pairing_frames_test.dart
```

预期：`All tests passed!`，7 个测试。

- [ ] **Step 5: 全量 analyze 与全量测试**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
```

预期：analyze 只剩 49 条既存 info（全在 `test/` 与 `tool/`），退出码 0；测试除 `command_palette_overlay_test.dart` 与 `pty_launch_environment_test.dart` 两个既存失败外全绿。**若 analyze 报出 `sealed` 穷举错误，说明 Step 3 的两个防御 `case` 漏了一处。**

- [ ] **Step 6: 提交**

```bash
cd /Users/yitouxiaomaolv/git/cmux && git add \
  client/lib/services/pairing/pairing_frames.dart \
  client/lib/services/pairing/pairing_rpc_handler.dart \
  client/lib/services/pairing/pairing_client.dart \
  client/test/services/pairing/pairing_frames_test.dart && \
git commit -m "feat(pairing): add the upload frame kind

Chunks stay binary rather than base64 JSON so a phone photo does not pay
33% inflation and a jsonEncode per chunk.

PairingFrame is sealed, so both switches over it get a defensive case in the
same commit rather than being left broken for two tasks — every commit on
this branch compiles and bisects. The client's case is permanent (the phone
sends upload frames and never receives them); the handler's is replaced with
real chunk handling later."
```

---

### Task 2: shell 引用纯函数

**Files:**
- Create: `client/lib/utils/shell_quote.dart`
- Test: `client/test/utils/shell_quote_test.dart`

**Interfaces:**
- Consumes: 无（本任务与 Task 1 无耦合，可并行）。
- Produces: `String shellQuotePath(String path)`

**为什么需要它：** 宿主回的绝对路径要插进 Composer 让用户直接回车。cwd 带空格时 `cat /Users/me/My Project/photo.jpg` 会被 shell 拆成两个参数 —— 插进去就不能用，等于这个功能在带空格的路径下失效。

- [ ] **Step 1: 写失败的测试**

`client/test/utils/shell_quote_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/shell_quote.dart';

void main() {
  test('leaves a plain path alone', () {
    // Quoting an already-safe path would be noise in the composer.
    expect(shellQuotePath('/home/dev/app/photo.jpg'), '/home/dev/app/photo.jpg');
  });

  test('leaves dots, dashes and underscores alone', () {
    expect(shellQuotePath('/a/b-c/d_e.f.jpg'), '/a/b-c/d_e.f.jpg');
  });

  test('quotes a path containing a space', () {
    // The whole reason this exists: unquoted, the shell splits this into two
    // arguments and the command fails.
    expect(
      shellQuotePath('/Users/me/My Project/photo.jpg'),
      "'/Users/me/My Project/photo.jpg'",
    );
  });

  test('quotes shell metacharacters', () {
    for (final path in [
      '/a/b\$c',
      '/a/b`c',
      '/a/b&c',
      '/a/b;c',
      '/a/b|c',
      '/a/b(c)',
      '/a/b*c',
      '/a/b?c',
      '/a/b#c',
      '/a/b!c',
      '/a/b\nc',
      '/a/b\tc',
    ]) {
      expect(shellQuotePath(path), startsWith("'"), reason: path);
      expect(shellQuotePath(path), endsWith("'"), reason: path);
    }
  });

  test('escapes an embedded single quote', () {
    // Inside single quotes nothing is special except the quote itself, so it
    // has to be closed, escaped, and reopened.
    expect(shellQuotePath("/a/it's/b.jpg"), r"'/a/it'\''s/b.jpg'");
  });

  test('escapes several embedded single quotes', () {
    expect(shellQuotePath("/a/'/'/b"), r"'/a/'\''/'\''/b'");
  });

  test('quotes a path made only of a single quote', () {
    expect(shellQuotePath("'"), r"''\'''");
  });

  test('quotes an empty string rather than emitting nothing', () {
    // An empty bare word would vanish from the command line; '' is one empty
    // argument, which is at least visible.
    expect(shellQuotePath(''), "''");
  });

  test('quotes a non-ASCII path', () {
    // Most shells cope, but the safe set is deliberately ASCII-only so we never
    // have to reason about locale-dependent word splitting.
    expect(shellQuotePath('/a/照片.jpg'), "'/a/照片.jpg'");
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd client && flutter test test/utils/shell_quote_test.dart
```

预期：`Target of URI doesn't exist: 'package:teampilot/utils/shell_quote.dart'`。

- [ ] **Step 3: 写 `shell_quote.dart`**

```dart
/// Characters a POSIX shell leaves alone in a bare word.
///
/// Deliberately ASCII-only and deliberately small: anything outside it gets
/// quoted, so we never have to reason about locale-dependent word splitting or
/// about which shell treats which byte specially.
final _safe = RegExp(r'^[A-Za-z0-9._/-]+$');

/// Renders [path] so a POSIX shell receives it as exactly one argument.
///
/// A path with a space in it is the reason this exists: pasted bare into a
/// terminal, `/Users/me/My Project/photo.jpg` becomes two arguments and the
/// command fails, which makes the whole upload useless on any machine whose
/// paths contain spaces.
///
/// Single quotes are the strong form — inside them nothing is special except
/// the quote itself, which is closed, backslash-escaped, and reopened.
String shellQuotePath(String path) {
  if (path.isNotEmpty && _safe.hasMatch(path)) return path;
  return "'${path.replaceAll("'", r"'\''")}'";
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd client && flutter test test/utils/shell_quote_test.dart
```

预期：`All tests passed!`，9 个测试。

- [ ] **Step 5: analyze 并提交**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/utils/shell_quote.dart test/utils/shell_quote_test.dart
cd /Users/yitouxiaomaolv/git/cmux && git add \
  client/lib/utils/shell_quote.dart \
  client/test/utils/shell_quote_test.dart && \
git commit -m "feat: add shellQuotePath

The composer inserts a host path for the user to run. Unquoted, any cwd
containing a space splits into two arguments and the command fails — which
would make image upload useless on those machines."
```

Task 1 若已合入，本任务的目录级 analyze 不受它的 `sealed` 报错影响（不同目录）。

---

### Task 3: 宿主侧组装与校验

**Files:**
- Create: `client/lib/services/pairing/pairing_upload_receiver.dart`
- Test: `client/test/services/pairing/pairing_upload_receiver_test.dart`

**Interfaces:**
- Consumes: 无（不依赖 Task 1 的帧类型 —— receiver 收的是已解出的 `transferId`/`chunkIndex`/`bytes`，不认识线格式）。
- Produces:
  - `typedef PairingUploadSink = Future<String> Function({required String workspaceId, required String cwd, required String filename, required List<int> bytes})`
  - `class UploadBeginResult` — `.ok(int transferId, int chunkSize)` / `.error(String code)`；字段 `transferId`、`chunkSize`、`code`；getter `isOk`
  - `class UploadChunkResult` — `.ok(int received)` / `.error(String code)`；字段 `received`、`code`；getter `isOk`
  - `class UploadCommitResult` — `.ok(String path)` / `.error(String code)`；字段 `path`、`code`；getter `isOk`
  - `class PairingUploadReceiver` — 构造 `PairingUploadReceiver({required PairingUploadSink sink, int maxBytes = 25 * 1024 * 1024, int chunkSize = 64 * 1024})`；方法 `UploadBeginResult begin({required String workspaceId, required String cwd, required String filename, required int size})`、`UploadChunkResult chunk(int transferId, int chunkIndex, List<int> bytes)`、`Future<UploadCommitResult> commit(int transferId)`、`void abandon(int transferId)`、`void abandonAll()`
  - `const uploadImageExtensions = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'heic'}`

**错误码：** `too_large`、`unsupported_type`、`bad_filename`、`write_failed`、`unknown_transfer`。（`no_target` 由 handler 与 sink 产生，不在 receiver 里。）

**`too_large` 也覆盖声明大小为负数**的畸形请求 —— 一个码管「声明大小不在可接受区间」，在代码注释里写明这一点，别让人以为漏了校验。声明大小为 0 是允许的（空文件无害，`commit` 的大小核对自然通过）。

- [ ] **Step 1: 写失败的测试**

`client/test/services/pairing/pairing_upload_receiver_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/pairing/pairing_upload_receiver.dart';

void main() {
  late List<({String workspaceId, String cwd, String filename, int length})>
      written;
  late Object? sinkError;
  late String sinkPath;

  PairingUploadReceiver build({int maxBytes = 1024, int chunkSize = 4}) {
    return PairingUploadReceiver(
      maxBytes: maxBytes,
      chunkSize: chunkSize,
      sink:
          ({
            required String workspaceId,
            required String cwd,
            required String filename,
            required List<int> bytes,
          }) async {
            final error = sinkError;
            if (error != null) throw error;
            written.add((
              workspaceId: workspaceId,
              cwd: cwd,
              filename: filename,
              length: bytes.length,
            ));
            return sinkPath;
          },
    );
  }

  /// A successful begin for a 6-byte photo.jpg.
  UploadBeginResult beginPhoto(PairingUploadReceiver receiver, {int size = 6}) =>
      receiver.begin(
        workspaceId: 'ws-1',
        cwd: '/home/dev/app',
        filename: 'photo.jpg',
        size: size,
      );

  setUp(() {
    written = [];
    sinkError = null;
    sinkPath = '/home/dev/app/photo.jpg';
  });

  group('begin', () {
    test('returns a transfer id and the host-chosen chunk size', () {
      final receiver = build(chunkSize: 4);
      final result = beginPhoto(receiver);
      expect(result.isOk, isTrue);
      expect(result.chunkSize, 4, reason: 'the host dictates the chunk size');
      expect(result.transferId, greaterThan(0));
    });

    test('hands out distinct transfer ids', () {
      final receiver = build();
      expect(
        beginPhoto(receiver).transferId,
        isNot(beginPhoto(receiver).transferId),
      );
    });

    test('rejects a declared size over the cap', () {
      final result = build(maxBytes: 10).begin(
        workspaceId: 'ws-1',
        cwd: '/c',
        filename: 'a.png',
        size: 11,
      );
      expect(result.isOk, isFalse);
      expect(result.code, 'too_large');
    });

    test('accepts a declared size exactly at the cap', () {
      final result = build(maxBytes: 10).begin(
        workspaceId: 'ws-1',
        cwd: '/c',
        filename: 'a.png',
        size: 10,
      );
      expect(result.isOk, isTrue);
    });

    test('rejects a negative declared size', () {
      // Malformed request; the same range check covers it, which is why the
      // code name reads as "out of range" rather than literally "too big".
      final result = build().begin(
        workspaceId: 'ws-1',
        cwd: '/c',
        filename: 'a.png',
        size: -1,
      );
      expect(result.code, 'too_large');
    });

    test('accepts every allowlisted extension, in any case', () {
      final receiver = build();
      for (final ext in uploadImageExtensions) {
        for (final name in ['a.$ext', 'a.${ext.toUpperCase()}']) {
          final result = receiver.begin(
            workspaceId: 'ws-1',
            cwd: '/c',
            filename: name,
            size: 1,
          );
          expect(result.isOk, isTrue, reason: name);
        }
      }
    });

    test('allowlists heic', () {
      // iPhones shoot HEIC by default and image_picker's conversion is not
      // reliable across versions; omitting it fails randomly on iOS.
      expect(uploadImageExtensions, contains('heic'));
    });

    test('rejects a non-image extension', () {
      for (final name in ['a.sh', 'a.txt', 'a.dart', 'a.png.sh']) {
        final result = build().begin(
          workspaceId: 'ws-1',
          cwd: '/c',
          filename: name,
          size: 1,
        );
        expect(result.code, 'unsupported_type', reason: name);
      }
    });

    test('rejects a filename with no extension', () {
      expect(
        build()
            .begin(workspaceId: 'ws-1', cwd: '/c', filename: 'photo', size: 1)
            .code,
        'unsupported_type',
      );
    });

    test('rejects any filename carrying a path component', () {
      // Rejected rather than basename'd: a phone sending a path is buggy or
      // hostile, and silently rewriting it hides that. Backslashes matter too —
      // a posix basename would not strip the Windows-style form.
      for (final name in [
        '../photo.jpg',
        '/etc/photo.jpg',
        'a/b.jpg',
        r'..\..\photo.jpg',
        r'a\b.jpg',
        '.',
        '..',
        '',
      ]) {
        final result = build().begin(
          workspaceId: 'ws-1',
          cwd: '/c',
          filename: name,
          size: 1,
        );
        expect(result.code, 'bad_filename', reason: 'name: $name');
      }
    });

    test('rejects a filename containing a null byte', () {
      // A NUL truncates the path at the C layer, so 'photo\x00.sh' could pass an
      // extension check and land as 'photo'.
      expect(
        build()
            .begin(
              workspaceId: 'ws-1',
              cwd: '/c',
              filename: 'photo\x00.jpg',
              size: 1,
            )
            .code,
        'bad_filename',
      );
    });
  });

  group('chunk', () {
    test('accumulates in order and reports the running total', () {
      final receiver = build(chunkSize: 4);
      final id = beginPhoto(receiver).transferId;
      expect(receiver.chunk(id, 0, const [1, 2, 3, 4]).received, 4);
      expect(receiver.chunk(id, 1, const [5, 6]).received, 6);
    });

    test('rejects an unknown transfer id', () {
      expect(build().chunk(999, 0, const [1]).code, 'unknown_transfer');
    });

    test('abandons the transfer on a gap in the chunk index', () {
      // WebSocket preserves order, so a gap means something is wrong. Silently
      // writing a file with a hole in it would be worse than failing.
      final receiver = build(chunkSize: 4);
      final id = beginPhoto(receiver).transferId;
      receiver.chunk(id, 0, const [1, 2, 3, 4]);
      expect(receiver.chunk(id, 2, const [5, 6]).code, 'write_failed');
      expect(
        receiver.chunk(id, 1, const [5, 6]).code,
        'unknown_transfer',
        reason: 'the transfer is gone, not merely erroring',
      );
    });

    test('abandons the transfer when the bytes exceed the declared size', () {
      final receiver = build(chunkSize: 4);
      final id = beginPhoto(receiver, size: 6).transferId;
      receiver.chunk(id, 0, const [1, 2, 3, 4]);
      expect(receiver.chunk(id, 1, const [5, 6, 7, 8]).code, 'too_large');
      expect(receiver.chunk(id, 2, const [9]).code, 'unknown_transfer');
    });
  });

  group('commit', () {
    test('hands the assembled bytes to the sink and returns its path', () async {
      final receiver = build(chunkSize: 4);
      final id = beginPhoto(receiver).transferId;
      receiver.chunk(id, 0, const [1, 2, 3, 4]);
      receiver.chunk(id, 1, const [5, 6]);

      final result = await receiver.commit(id);

      expect(result.isOk, isTrue);
      expect(result.path, '/home/dev/app/photo.jpg');
      expect(written.single.workspaceId, 'ws-1');
      expect(written.single.cwd, '/home/dev/app');
      expect(written.single.filename, 'photo.jpg');
      expect(written.single.length, 6);
    });

    test('rejects an unknown transfer id', () async {
      expect((await build().commit(999)).code, 'unknown_transfer');
    });

    test('rejects a short transfer without calling the sink', () async {
      // Truncation is what the size check exists to catch; half a file on disk
      // is worse than no file.
      final receiver = build(chunkSize: 4);
      final id = beginPhoto(receiver, size: 6).transferId;
      receiver.chunk(id, 0, const [1, 2, 3, 4]);
      expect((await receiver.commit(id)).code, 'write_failed');
      expect(written, isEmpty);
    });

    test('reports write_failed when the sink throws', () async {
      final receiver = build(chunkSize: 4);
      final id = beginPhoto(receiver, size: 2).transferId;
      receiver.chunk(id, 0, const [1, 2]);
      sinkError = StateError('disk full');
      expect((await receiver.commit(id)).code, 'write_failed');
    });

    test('drops the transfer after a successful commit', () async {
      final receiver = build(chunkSize: 4);
      final id = beginPhoto(receiver, size: 2).transferId;
      receiver.chunk(id, 0, const [1, 2]);
      await receiver.commit(id);
      expect((await receiver.commit(id)).code, 'unknown_transfer');
    });
  });

  group('abandon', () {
    test('abandon drops one transfer', () {
      final receiver = build();
      final id = beginPhoto(receiver).transferId;
      receiver.abandon(id);
      expect(receiver.chunk(id, 0, const [1]).code, 'unknown_transfer');
    });

    test('abandon of an unknown id is harmless', () {
      expect(() => build().abandon(999), returnsNormally);
    });

    test('abandonAll drops every in-flight transfer', () {
      // The connection closing must release the bytes of every unfinished
      // transfer, or a phone that reconnects repeatedly feeds the desktop's
      // memory.
      final receiver = build();
      final a = beginPhoto(receiver).transferId;
      final b = beginPhoto(receiver).transferId;
      receiver.abandonAll();
      expect(receiver.chunk(a, 0, const [1]).code, 'unknown_transfer');
      expect(receiver.chunk(b, 0, const [1]).code, 'unknown_transfer');
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd client && flutter test test/services/pairing/pairing_upload_receiver_test.dart
```

预期：`Target of URI doesn't exist: 'package:teampilot/services/pairing/pairing_upload_receiver.dart'`。

- [ ] **Step 3: 写 `pairing_upload_receiver.dart`**

要求，逐条照做：

- 只 import `dart:typed_data`（`BytesBuilder`）与 `../../utils/logging/logger_utils.dart`。**不 import 任何 `services/io/` 或 `services/storage/`** —— receiver 对文件系统一无所知，那是 sink 的事。
- `const uploadImageExtensions = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'heic'}`，顶层常量。
- 私有 `_Transfer` 持 `workspaceId`、`cwd`、`filename`、`declaredSize`、`BytesBuilder(copy: false)`、`nextIndex`（初值 0）、`received`（初值 0）。
- `begin`：先校验文件名 → 再扩展名 → 再大小；任一失败立即返回对应 `error`，**不分配 transferId**（分配后再拒会让 id 序列出现空洞，看起来像丢包）。通过后 `_nextId++` 分配、存表、返回 `ok(id, chunkSize)`。
- 文件名校验，任一命中即 `bad_filename`：`name.isEmpty`、`name == '.'`、`name == '..'`、`name.contains('/')`、`name.contains(r'\')`、`name.contains('\x00')`。
- 扩展名校验：取最后一个 `.` 之后的部分；没有 `.`、`.` 是最后一个字符、或 `toLowerCase()` 不在白名单 → `unsupported_type`。注意 `a.png.sh` 的扩展名是 `sh`，天然被拒。
- 大小校验：`size < 0 || size > maxBytes` → `too_large`。注释写明这一个码同时覆盖负数这种畸形请求。
- `chunk`：表里没有 → `unknown_transfer`；`chunkIndex != nextIndex` → `abandon(id)` 后 `error('write_failed')`；`received + bytes.length > declaredSize` → `abandon(id)` 后 `error('too_large')`；否则 `add(bytes)`、`received += bytes.length`、`nextIndex++`、返回 `ok(received)`。
- `commit`：表里没有 → `unknown_transfer`；`received != declaredSize` → `abandon(id)` 后 `error('write_failed')`；否则**先从表里移除**（无论 sink 成败都不该留在表里）再 `await sink(...)`，成功回 `ok(path)`，`on Object catch (e, st)` 时 `AppLogger.instance.w('Pairing upload sink failed ($e)', error: e, stackTrace: st)` 后回 `error('write_failed')`。
- `abandon(int id)`：`_transfers.remove(id)`，不存在也不报错。`abandonAll()`：`_transfers.clear()`。
- 类文档注释写明两件事：本类知道协议、不知道文件系统；`abandonAll` 必须在连接关闭时调用，否则未完成 transfer 的字节会一直留在内存里。
- 文件不超过 ~180 行。

- [ ] **Step 4: 跑测试确认通过**

```bash
cd client && flutter test test/services/pairing/pairing_upload_receiver_test.dart
```

预期：`All tests passed!`，21 个测试。

- [ ] **Step 5: 目录级 analyze 并提交**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/pairing/pairing_upload_receiver.dart test/services/pairing/pairing_upload_receiver_test.dart
cd /Users/yitouxiaomaolv/git/cmux && git add \
  client/lib/services/pairing/pairing_upload_receiver.dart \
  client/test/services/pairing/pairing_upload_receiver_test.dart && \
git commit -m "feat(pairing): add the host-side upload receiver

Knows the protocol, knows nothing about filesystems — resolving the pane's
runtime target is the injected sink's job, which keeps this testable with a
fake and keeps storage out of the pairing layer.

Filenames carrying a path component are rejected rather than basename'd: a
phone sending one is buggy or hostile, and rewriting it silently hides
that. Backslashes and NULs are rejected too, since a posix basename would
strip neither."
```

---

### Task 4: 手机侧分片与信用窗口

**Files:**
- Create: `client/lib/services/pairing/pairing_upload_sender.dart`
- Test: `client/test/services/pairing/pairing_upload_sender_test.dart`

**Interfaces:**
- Consumes: `PairingCodec.encodeUpload(int transferId, int chunkIndex, Uint8List bytes)`、`UploadFrame`（Task 1，`lib/services/pairing/pairing_frames.dart`）。
- Produces:
  - `class PairingUploadAck` — `const PairingUploadAck({required int transferId, required int received})`
  - `class PairingUploadException implements Exception` — `const PairingUploadException(String code)`；字段 `code`
  - `class PairingUploadSender` — 构造 `PairingUploadSender({required Future<Map<String, Object?>> Function(String method, Map<String, Object?> params) rpc, required void Function(Uint8List frame) send, required Stream<PairingUploadAck> acks, int windowChunks = 16, Duration ackTimeout = const Duration(seconds: 30)})`；方法 `Future<String> upload({required int sub, required String filename, required Uint8List bytes, void Function(int sent, int total)? onProgress})`

**信用窗口为什么必须有：** 手机→宿主方向今天零背压，`WsTransport.send` 直接 `_socket.add`，而 Dart 的 `WebSocket` 无界缓冲。25 MB 分成 400 片背靠背写出去会在手机上堆成真实内存尖峰。窗口把在途量钉在 `windowChunks * chunkSize`（生产 1 MiB），代价是每 MiB 一个 RTT。

- [ ] **Step 1: 写失败的测试**

`client/test/services/pairing/pairing_upload_sender_test.dart`：

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/pairing/pairing_frames.dart';
import 'package:teampilot/services/pairing/pairing_upload_sender.dart';

void main() {
  late List<({String method, Map<String, Object?> params})> calls;
  late List<Uint8List> sentFrames;
  late StreamController<PairingUploadAck> acks;
  late Map<String, Object?> beginReply;
  late Map<String, Object?> commitReply;
  late Object? rpcError;

  /// The upload frames the sender wrote, decoded.
  List<UploadFrame> uploads() =>
      sentFrames.map((f) => PairingCodec.decode(f) as UploadFrame).toList();

  PairingUploadSender build({
    int windowChunks = 2,
    Duration ackTimeout = const Duration(seconds: 30),
  }) {
    return PairingUploadSender(
      windowChunks: windowChunks,
      ackTimeout: ackTimeout,
      acks: acks.stream,
      send: sentFrames.add,
      rpc: (method, params) async {
        calls.add((method: method, params: params));
        final error = rpcError;
        if (error != null) throw error;
        return method == 'upload.begin' ? beginReply : commitReply;
      },
    );
  }

  setUp(() {
    calls = [];
    sentFrames = [];
    acks = StreamController<PairingUploadAck>.broadcast();
    rpcError = null;
    beginReply = {'ok': true, 'transferId': 7, 'chunkSize': 4};
    commitReply = {'ok': true, 'path': '/home/dev/app/photo.jpg'};
  });

  tearDown(() => acks.close());

  Uint8List payload(int length) =>
      Uint8List.fromList(List.generate(length, (i) => i % 256));

  test('begins, chunks in order, then commits and returns the host path',
      () async {
    final path = await build(windowChunks: 100).upload(
      sub: 3,
      filename: 'photo.jpg',
      bytes: payload(10),
    );

    expect(path, '/home/dev/app/photo.jpg');
    expect(calls.first.method, 'upload.begin');
    expect(calls.first.params, {'sub': 3, 'filename': 'photo.jpg', 'size': 10});
    expect(calls.last.method, 'upload.commit');
    expect(calls.last.params, {'transferId': 7});

    final frames = uploads();
    expect(frames, hasLength(3), reason: '10 bytes at a chunk size of 4');
    expect(frames.map((f) => f.chunkIndex), [0, 1, 2]);
    expect(frames.every((f) => f.transferId == 7), isTrue);
    expect(frames[0].bytes, hasLength(4));
    expect(frames[2].bytes, hasLength(2), reason: 'the tail is short');
  });

  test('slices by the chunk size the host chose, not a hardcoded one',
      () async {
    // The host dictates chunk size so it can be retuned without shipping a new
    // phone build.
    beginReply = {'ok': true, 'transferId': 1, 'chunkSize': 3};
    await build(
      windowChunks: 100,
    ).upload(sub: 1, filename: 'a.png', bytes: payload(9));
    expect(uploads(), hasLength(3));
    expect(uploads().first.bytes, hasLength(3));
  });

  test('holds at the credit window until an ack arrives', () async {
    // The point of the window: without it, 25 MB of chunks go into an unbounded
    // socket buffer at once. windowChunks 2 x chunkSize 4 = 8 bytes in flight.
    final sender = build(windowChunks: 2);
    final done = sender.upload(sub: 1, filename: 'a.png', bytes: payload(20));

    await Future<void>.delayed(Duration.zero);
    expect(uploads(), hasLength(2), reason: 'window full, must wait');

    acks.add(const PairingUploadAck(transferId: 7, received: 8));
    await Future<void>.delayed(Duration.zero);
    expect(uploads(), hasLength(4), reason: 'window reopened by one full ack');

    acks.add(const PairingUploadAck(transferId: 7, received: 20));
    await done;
    expect(uploads(), hasLength(5));
  });

  test('ignores acks belonging to a different transfer', () async {
    final sender = build(windowChunks: 2);
    final done = sender.upload(sub: 1, filename: 'a.png', bytes: payload(20));
    await Future<void>.delayed(Duration.zero);

    acks.add(const PairingUploadAck(transferId: 999, received: 20));
    await Future<void>.delayed(Duration.zero);
    expect(uploads(), hasLength(2), reason: 'still blocked');

    acks.add(const PairingUploadAck(transferId: 7, received: 20));
    await done;
  });

  test('throws with the host code and sends nothing when begin is refused',
      () async {
    // A rejected begin must not put a single byte on the wire.
    beginReply = {'ok': false, 'code': 'too_large'};
    await expectLater(
      build().upload(sub: 1, filename: 'huge.png', bytes: payload(20)),
      throwsA(
        isA<PairingUploadException>().having((e) => e.code, 'code', 'too_large'),
      ),
    );
    expect(sentFrames, isEmpty);
    expect(calls.map((c) => c.method), ['upload.begin']);
  });

  test('throws when commit reports a failure', () async {
    commitReply = {'ok': false, 'code': 'write_failed'};
    await expectLater(
      build(
        windowChunks: 100,
      ).upload(sub: 1, filename: 'a.png', bytes: payload(4)),
      throwsA(
        isA<PairingUploadException>().having(
          (e) => e.code,
          'code',
          'write_failed',
        ),
      ),
    );
  });

  test('propagates an rpc failure and never commits', () async {
    rpcError = TimeoutException('RPC upload.begin timed out');
    await expectLater(
      build().upload(sub: 1, filename: 'a.png', bytes: payload(4)),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls.map((c) => c.method), ['upload.begin']);
  });

  test('times out waiting for an ack that never comes', () async {
    final sender = build(
      windowChunks: 1,
      ackTimeout: const Duration(milliseconds: 20),
    );
    await expectLater(
      sender.upload(sub: 1, filename: 'a.png', bytes: payload(20)),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('reports progress monotonically, ending at the total', () async {
    final seen = <int>[];
    await build(windowChunks: 100).upload(
      sub: 1,
      filename: 'a.png',
      bytes: payload(10),
      onProgress: (sent, total) {
        expect(total, 10);
        seen.add(sent);
      },
    );
    expect(seen, [4, 8, 10]);
  });

  test('handles an empty payload without sending a chunk', () async {
    // Degenerate but reachable if a picker returns a zero-byte file; it must
    // commit rather than hang.
    final path = await build().upload(
      sub: 1,
      filename: 'a.png',
      bytes: Uint8List(0),
    );
    expect(path, '/home/dev/app/photo.jpg');
    expect(sentFrames, isEmpty);
    expect(calls.map((c) => c.method), ['upload.begin', 'upload.commit']);
  });

  test('stops listening to acks once the upload settles', () async {
    // A leaked subscription on a broadcast stream would outlive every upload,
    // one per attempt, for the life of the connection.
    await build(
      windowChunks: 100,
    ).upload(sub: 1, filename: 'a.png', bytes: payload(4));
    expect(acks.hasListener, isFalse);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd client && flutter test test/services/pairing/pairing_upload_sender_test.dart
```

预期：`Target of URI doesn't exist: 'package:teampilot/services/pairing/pairing_upload_sender.dart'`。

- [ ] **Step 3: 写 `pairing_upload_sender.dart`**

import `dart:async`、`dart:math`（`min`）、`dart:typed_data`、`pairing_frames.dart`。**不 import 任何 socket 或 `pairing_client.dart`** —— 注入 `rpc`/`send`/`acks` 就是为了不碰 socket。

`upload` 的完整实现：

```dart
  Future<String> upload({
    required int sub,
    required String filename,
    required Uint8List bytes,
    void Function(int sent, int total)? onProgress,
  }) async {
    final begin = await _rpc('upload.begin', {
      'sub': sub,
      'filename': filename,
      'size': bytes.length,
    });
    if (begin['ok'] != true) {
      throw PairingUploadException(begin['code'] as String? ?? 'write_failed');
    }
    final transferId = begin['transferId']! as int;
    final chunkSize = begin['chunkSize']! as int;
    final windowBytes = chunkSize * _windowChunks;

    var sent = 0;
    var acked = 0;
    Completer<void>? waiter;
    final ackSub = _acks.where((ack) => ack.transferId == transferId).listen((
      ack,
    ) {
      if (ack.received > acked) acked = ack.received;
      waiter?.complete();
      waiter = null;
    });
    try {
      var index = 0;
      var offset = 0;
      while (offset < bytes.length) {
        // Bound what is in flight. Dart's WebSocket buffers without limit, so
        // without this every chunk of a large photo lands in memory at once.
        while (sent - acked >= windowBytes) {
          final gate = Completer<void>();
          waiter = gate;
          await gate.future.timeout(_ackTimeout);
        }
        final end = min(offset + chunkSize, bytes.length);
        _send(
          PairingCodec.encodeUpload(
            transferId,
            index,
            Uint8List.sublistView(bytes, offset, end),
          ),
        );
        sent = end;
        onProgress?.call(sent, bytes.length);
        offset = end;
        index++;
      }
      final commit = await _rpc('upload.commit', {'transferId': transferId});
      if (commit['ok'] != true) {
        throw PairingUploadException(
          commit['code'] as String? ?? 'write_failed',
        );
      }
      return commit['path']! as String;
    } finally {
      await ackSub.cancel();
    }
  }
```

其余要求：

- `PairingUploadException.toString()` 返回 `'PairingUploadException: $code'`。
- `PairingUploadAck` 是纯值类，不需要 `==`。
- 类文档注释写明两件事：窗口存在的理由（Dart WebSocket 无界缓冲），以及 `chunkSize` 取自宿主回复而非本地常量的理由。
- 文件不超过 ~130 行。

- [ ] **Step 4: 跑测试确认通过**

```bash
cd client && flutter test test/services/pairing/pairing_upload_sender_test.dart
```

预期：`All tests passed!`，11 个测试。若 `holds at the credit window` 卡住不动，先查 `waiter` 是否在 ack 到达时真的被 complete 且置空。

- [ ] **Step 5: 目录级 analyze 并提交**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/pairing/pairing_upload_sender.dart test/services/pairing/pairing_upload_sender_test.dart
cd /Users/yitouxiaomaolv/git/cmux && git add \
  client/lib/services/pairing/pairing_upload_sender.dart \
  client/test/services/pairing/pairing_upload_sender_test.dart && \
git commit -m "feat(pairing): add the phone-side chunked upload sender

First flow control in this protocol. The phone-to-host direction has no
backpressure and Dart's WebSocket buffers without limit, so a 25 MB photo
written chunk-after-chunk would spike memory on the phone; a 16-chunk
credit window bounds it to 1 MiB at the cost of one RTT per MiB.

Chunk size comes from the host's begin reply rather than a local constant,
so it can be retuned without shipping a new phone build."
```

---

### Task 5: 宿主侧端到端接线

**Files:**
- Modify: `client/lib/services/pairing/pairing_rpc_handler.dart`
- Modify: `client/lib/services/pairing/pairing_connection.dart`
- Modify: `client/lib/services/pairing/lan_pairing_server.dart`
- Modify: `client/lib/app/app_shell.dart`
- Test: `client/test/services/pairing/pairing_rpc_handler_upload_test.dart`（新建）
- Test: 若 `client/test/services/pairing/` 下已有构造 `PairingRpcHandler` / `PairingConnection` / `LanPairingServer` 的测试，因新增必需参数而不再编译 —— 补参数即可，**断言、测试名、既有注释一个字不改**

**Interfaces:**
- Consumes: `PairingUploadReceiver`、`PairingUploadSink`、`UploadBeginResult`、`UploadChunkResult`、`UploadCommitResult`（Task 3）；`UploadFrame`（Task 1）。
- Produces: 宿主端完整可用的 `upload.begin` / `upload.commit` / `upload.ack`；无新公开类型。

**为什么四个文件一个任务：** sink 是 handler 的必需构造参数，必须一路穿到 `LanPairingServer` 才能由 bootstrap 提供。拆开会留下「协议认识 upload 但没有落点」的中间态，既不可测也不可审。

- [ ] **Step 1: 写失败的测试**

`client/test/services/pairing/pairing_rpc_handler_upload_test.dart`。**先读 `client/test/services/pairing/` 下已有的 handler 测试**（若有），沿用它构造 `SessionCatalog` 与假 `TerminalSession` 的方式，不要另创一套。若没有现成的 handler 测试，用一个最小的假 `SessionCatalogSource` 提供一个 `SessionCatalogEntry`，其 `ref.workspaceId` 为 `'ws-1'`，其 `session.runtimeTarget.workingDirectory` 为 `'/home/dev/app'`。

必须覆盖：

1. `terminal.subscribe` 之后，`upload.begin` 回 `{'ok': true, 'transferId': …, 'chunkSize': …}`，且 receiver 收到的 `workspaceId` 是 `'ws-1'`、`cwd` 是 `'/home/dev/app'`（用一个记录参数的假 receiver 或假 sink 断言）。
2. **未订阅的 `sub`** → `upload.begin` 回 `{'ok': false, 'code': 'no_target'}`，且 receiver 的 `begin` **一次都没被调用**（断言调用计数，不只断言回复）。
3. `UploadFrame` 经 `handle` 交给 receiver 的 `chunk`，参数 `transferId`/`chunkIndex`/`bytes` 逐一正确。
4. `chunk` 返回 ok 时，宿主发出一条 `{'method': 'upload.ack', 'params': {'transferId': …, 'received': …}}` 的 JSON 帧（解码 `_send` 收到的帧断言）。
5. `chunk` 返回 error 时，宿主**不发 ack**（否则手机会以为窗口开了继续灌）。
6. `upload.commit` 回 `{'ok': true, 'path': …}`，路径取自 receiver。
7. receiver 报错码时 `commit` 回 `{'ok': false, 'code': <该码>}`。
8. `dispose()` 调用 receiver 的 `abandonAll()`（断言被调用）。

期望抛出一律钉类型；不写恒真断言。

- [ ] **Step 2: 跑测试确认失败**

```bash
cd client && flutter test test/services/pairing/pairing_rpc_handler_upload_test.dart
```

预期：编译失败，`PairingRpcHandler` 没有 `uploadSink`/`uploadReceiver` 参数。

- [ ] **Step 3: 改 `pairing_rpc_handler.dart`**

1. 构造函数新增 **必需** 参数 `required PairingUploadSink uploadSink`，内部自建 receiver（把上限与分片大小也做成可选构造参数以便测试注入小值）：

```dart
    required PairingUploadSink uploadSink,
    int uploadMaxBytes = 25 * 1024 * 1024,
    int uploadChunkSize = 64 * 1024,
  }) : _uploads = PairingUploadReceiver(
         sink: uploadSink,
         maxBytes: uploadMaxBytes,
         chunkSize: uploadChunkSize,
       ),
```

2. `handle` 的 `switch (frame)` 里，Task 1 留下的 `case UploadFrame(): break;` 换成真实处理：

```dart
      case UploadFrame(:final transferId, :final chunkIndex, :final bytes):
        _onUploadChunk(transferId, chunkIndex, bytes);
```

3. `_handleJson` 的 `switch (method)` 新增两个 case，放在 `'ping'` 之前：

```dart
      case 'upload.begin':
        _uploadBegin(id, params);
      case 'upload.commit':
        _uploadCommit(id, params);
```

4. 三个新方法：

```dart
  /// Upload replies carry success in the *result* envelope rather than the
  /// JSON-RPC `error` field: [_replyError] sends a bare string that the client
  /// turns into `Exception(message)`, so a structured code could not survive
  /// the trip. Do not "fix" this back to the error channel.
  void _uploadBegin(Object? id, Map<String, Object?> params) {
    final sub = params['sub'];
    final filename = params['filename'];
    final size = params['size'];
    final record = sub is int ? _subs[sub] : null;
    if (record == null || filename is! String || size is! int) {
      _replyResult(id, const {'ok': false, 'code': 'no_target'});
      return;
    }
    final entry = _catalog.resolve(record.catalogId);
    if (entry == null) {
      _replyResult(id, const {'ok': false, 'code': 'no_target'});
      return;
    }
    final result = _uploads.begin(
      workspaceId: entry.ref.workspaceId,
      cwd: record.session.runtimeTarget.workingDirectory,
      filename: filename,
      size: size,
    );
    _replyResult(id, result.isOk
        ? {'ok': true, 'transferId': result.transferId, 'chunkSize': result.chunkSize}
        : {'ok': false, 'code': result.code});
  }

  void _onUploadChunk(int transferId, int chunkIndex, Uint8List bytes) {
    final result = _uploads.chunk(transferId, chunkIndex, bytes);
    // Only a good chunk reopens the credit window. Acking a rejected chunk
    // would let the phone keep streaming into a dead transfer.
    if (!result.isOk) return;
    _send(PairingCodec.encodeJson({
      'method': 'upload.ack',
      'params': {'transferId': transferId, 'received': result.received},
    }));
  }

  Future<void> _uploadCommit(Object? id, Map<String, Object?> params) async {
    final transferId = params['transferId'];
    if (transferId is! int) {
      _replyResult(id, const {'ok': false, 'code': 'unknown_transfer'});
      return;
    }
    final result = await _uploads.commit(transferId);
    _replyResult(id, result.isOk
        ? {'ok': true, 'path': result.path}
        : {'ok': false, 'code': result.code});
  }
```

`_handleJson` 是同步方法而 `_uploadCommit` 是异步 —— 用 `unawaited(_uploadCommit(id, params))` 调用并 import `dart:async`（文件已 import）。

5. `dispose()` 里在清 `_subs` 之前加 `_uploads.abandonAll();`，注释写明：连接关闭必须释放未完成 transfer 的字节，否则反复断连的手机能喂满桌面内存。

6. 类文档注释里的方法清单补上三个新方法。

- [ ] **Step 4: 穿参数**

`pairing_connection.dart`：构造函数新增 `required PairingUploadSink uploadSink`，存字段，在创建 `PairingRpcHandler` 处传下去（`_acceptAuth` 里）。

`lan_pairing_server.dart`：构造函数新增 `required PairingUploadSink uploadSink`，存字段，在 `_accept` 创建 `PairingConnection` 处传下去。

两处都只加参数与转发，不改其他逻辑。

- [ ] **Step 5: 在 `app_shell.dart` 实现 sink**

`serverFactory()` 之前加一个本地函数，`serverFactory` 里传 `uploadSink: pairingUploadSink`：

```dart
    // Phone → desktop image upload. Resolving the pane's machine lives here
    // rather than in the pairing layer: this is the only place that has both
    // the session repository and the runtime-context registry.
    Future<String> pairingUploadSink({
      required String workspaceId,
      required String cwd,
      required String filename,
      required List<int> bytes,
    }) async {
      final workspaces = await sessionRepo.loadWorkspacesIndex();
      final workspace = workspaces
          .where((w) => w.workspaceId == workspaceId)
          .firstOrNull;
      final folders = workspace?.folders ?? const <WorkspaceFolder>[];
      // Which machine owns this cwd. matchSubpaths so a pane launched in a
      // subdirectory of a folder still resolves to that folder's target.
      final targetId =
          targetIdForFolderPaths(folders, [cwd], matchSubpaths: true) ??
          (folders.isEmpty ? RuntimeTarget.localId : folders.first.targetId);
      final context = await sessionLifecycle.resolveWorkContextForTargetId(
        targetId,
      );
      final fs = context.filesystem;
      final pathContext = fs.pathContext;
      await fs.ensureDir(cwd);
      final destination = await _freeUploadPath(fs, pathContext, cwd, filename);
      await fs.writeBytes(destination, bytes);
      return destination;
    }
```

顶层新增私有 helper：

```dart
/// First unused path for [filename] in [cwd], suffixing `-1`, `-2`, … before the
/// extension.
///
/// Never overwriting is also what keeps a symlink planted in the cwd from being
/// followed: a pre-existing `photo.jpg` pointing at `/etc/passwd` makes us write
/// `photo-1.jpg` instead. Anyone changing this must know that.
Future<String> _freeUploadPath(
  Filesystem fs,
  p.Context pathContext,
  String cwd,
  String filename,
) async {
  final extension = pathContext.extension(filename);
  final stem = pathContext.basenameWithoutExtension(filename);
  for (var attempt = 0; attempt < 100; attempt++) {
    final candidate = attempt == 0
        ? filename
        : '$stem-$attempt$extension';
    final path = pathContext.join(cwd, candidate);
    final stat = await fs.stat(path);
    if (!stat.exists) return path;
  }
  // A cwd already holding 100 same-named files is either pathological or an
  // attempt to pin us in this loop.
  throw StateError('no free upload path for $filename in $cwd');
}
```

要求：

- `sessionLifecycle` 是 bootstrap 里已有的 `SessionLifecycleService` 实例；用它实际的变量名（**动手前先在文件里确认**，不要照抄这个名字）。
- 需要的 import：`../models/workspace.dart`（`WorkspaceFolder`）、`../models/workspace_topology.dart`（`targetIdForFolderPaths`）、`../models/runtime_target.dart`（`RuntimeTarget.localId`）、`../services/io/filesystem.dart`（`Filesystem`）、`package:path/path.dart as p`、`pairing_upload_receiver.dart`（`PairingUploadSink`）。文件可能已 import 其中一部分。
- `fs.stat(path)` 返回 `FsStat`；**先读 `lib/services/io/filesystem.dart` 确认判断存在性的字段名**（可能是 `exists`，也可能别的），照实际的写。
- **两个 `RuntimeTarget` 不能混**：`cwd` 来自 `session.runtimeTarget.workingDirectory`（`services/workspace_dnd/runtime_target.dart`，不连文件系统），`targetId` 与 `RuntimeTarget.localId` 来自 `models/runtime_target.dart`（能解析成 `RuntimeContext`）。

- [ ] **Step 6: 跑测试与全量 analyze**

```bash
cd client && flutter test test/services/pairing/
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

预期：pairing 目录全绿；analyze 只剩 49 条既存 info。**若 analyze 报出任何错误，先修再往下。**

- [ ] **Step 7: 提交**

```bash
git add \
  client/lib/services/pairing/pairing_rpc_handler.dart \
  client/lib/services/pairing/pairing_connection.dart \
  client/lib/services/pairing/lan_pairing_server.dart \
  client/lib/app/app_shell.dart \
  client/test/services/pairing/pairing_rpc_handler_upload_test.dart && \
git commit -m "feat(pairing): land uploaded bytes in the mirrored pane's cwd

The sink is threaded from bootstrap because that is the only place holding
both the session repository and the runtime-context registry; the pairing
layer stays ignorant of filesystems.

Never overwriting an existing name is load-bearing twice over: it protects
the user's files and it stops a symlink planted in the cwd from being
followed.

Only an accepted chunk emits an ack, so a rejected chunk closes the credit
window instead of inviting more bytes into a dead transfer."
```

若因新增必需参数改了既有测试的构造调用，把那些文件一并 `git add` 并在提交信息里点名 —— 只补参数，断言未动。

---

### Task 6: 手机侧客户端接线

**Files:**
- Modify: `client/lib/services/pairing/pairing_client.dart`
- Modify: `client/lib/cubits/pairing_client_cubit.dart`
- Test: `client/test/cubits/pairing_client_cubit_test.dart`（追加，**不改既有断言**）

**Interfaces:**
- Consumes: `PairingUploadSender`、`PairingUploadAck`、`PairingUploadException`（Task 4）；`UploadFrame`（Task 1）。
- Produces:
  - `Stream<PairingUploadAck> get PairingClient.uploadAcks`
  - `Future<String> PairingClient.uploadFile({required int sub, required String filename, required Uint8List bytes, void Function(int sent, int total)? onProgress})`
  - `Future<String> PairingClientCubit.uploadImage({required String filename, required Uint8List bytes, void Function(int sent, int total)? onProgress})`

- [ ] **Step 1: 改 `pairing_client.dart`**

1. `_onBytes` 的 `UploadFrame` 分支 Task 1 已加为永久性的防御忽略（手机只发不收），**本任务不动它**。

2. `_onJson` 在 `session.changed` 分支之后加：

```dart
    if (method == 'upload.ack') {
      final params = _params(data);
      final transferId = params['transferId'];
      final received = params['received'];
      if (transferId is int && received is int && !_uploadAcks.isClosed) {
        _uploadAcks.add(
          PairingUploadAck(transferId: transferId, received: received),
        );
      }
      return;
    }
```

3. 字段与 getter：

```dart
  final _uploadAcks = StreamController<PairingUploadAck>.broadcast();

  /// Credit-window receipts for in-flight uploads. Broadcast because each
  /// upload attaches its own filtered listener.
  Stream<PairingUploadAck> get uploadAcks => _uploadAcks.stream;
```

4. `uploadFile`，放在 `sendResize` 附近：

```dart
  Future<String> uploadFile({
    required int sub,
    required String filename,
    required Uint8List bytes,
    void Function(int sent, int total)? onProgress,
  }) {
    return PairingUploadSender(
      rpc: _rpc,
      send: _sendEncrypted,
      acks: uploadAcks,
    ).upload(
      sub: sub,
      filename: filename,
      bytes: bytes,
      onProgress: onProgress,
    );
  }
```

每次上传新建一个 sender 是有意的：它没有跨上传的状态，而单实例反而要管「当前是哪个 transfer」。

5. `_teardown()`（或该类关闭连接的地方）里关掉 `_uploadAcks`，与既有 `_sessionsChanged` 的处理放在一起。**先读那段代码确认既有关闭时机**，照它做。

- [ ] **Step 2: 改 `pairing_client_cubit.dart`**

紧挨 `sendResize` 加薄转发，照它的写法从 `_activeSubscription` 取 `sub`：

```dart
  /// Ships [bytes] to the host, which writes them into the mirrored pane's
  /// working directory and returns the absolute path it used.
  Future<String> uploadImage({
    required String filename,
    required Uint8List bytes,
    void Function(int sent, int total)? onProgress,
  }) {
    final sub = _activeSubscription;
    final client = _client;
    if (sub == null || client == null) {
      throw const PairingUploadException('no_target');
    }
    return client.uploadFile(
      sub: sub.sub,
      filename: filename,
      bytes: bytes,
      onProgress: onProgress,
    );
  }
```

这样 `ImageUploadCubit` 注入的函数签名里不带 `sub` —— 镜像页不需要知道订阅 id。

- [ ] **Step 3: 追加 cubit 测试**

在 `client/test/cubits/pairing_client_cubit_test.dart` **末尾追加**（既有 18 个测试一字不动）：未 mirroring 时 `uploadImage` 抛 `PairingUploadException` 且 `code` 为 `'no_target'`；mirroring 时把 `sub`、`filename`、`bytes` 原样转给假 client 的 `uploadFile` 并返回它给的路径。沿用该文件既有的假 `PairingClient` 构造方式（`clientFactory` 注入），不要另创一套。

- [ ] **Step 4: 跑测试与全量 analyze**

```bash
cd client && flutter test test/cubits/pairing_client_cubit_test.dart test/services/pairing/
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

预期：全绿；analyze 只剩 49 条既存 info。

- [ ] **Step 5: 跑全量测试并提交**

```bash
cd client && flutter test --exclude-tags integration
```

预期：除 `command_palette_overlay_test.dart` 与 `pty_launch_environment_test.dart` 两个既存失败外全绿。

```bash
cd /Users/yitouxiaomaolv/git/cmux && git add \
  client/lib/services/pairing/pairing_client.dart \
  client/lib/cubits/pairing_client_cubit.dart \
  client/test/cubits/pairing_client_cubit_test.dart && \
git commit -m "feat(pairing): expose uploadFile on the client

A fresh sender per upload: it holds no state across uploads, and a single
instance would have to track which transfer is current instead.

The cubit resolves the subscription id itself, matching sendInput and
sendResize, so callers above it never handle a wire id."
```

---

### Task 7: ImageUploadCubit

**Files:**
- Create: `client/lib/cubits/image_upload_cubit.dart`
- Test: `client/test/cubits/image_upload_cubit_test.dart`

**Interfaces:**
- Consumes: `PairingUploadException`（Task 4）。
- Produces:
  - `enum ImageUploadStatus { idle, picking, uploading }`
  - `enum ImageUploadFailure { tooLarge, unsupportedType, failed }`
  - `class PickedImage` — `const PickedImage({required String filename, required Uint8List bytes})`
  - `class ImageUploadState` — 字段 `ImageUploadStatus status`、`int sentBytes`、`int totalBytes`；getter `double get progress`；`copyWith`
  - `class ImageUploadCubit extends Cubit<ImageUploadState>` — 构造 `ImageUploadCubit({required Future<PickedImage?> Function() pickImage, required Future<String> Function({required String filename, required Uint8List bytes, void Function(int sent, int total)? onProgress}) upload, int maxBytes = 25 * 1024 * 1024})`；getter `Stream<String> get paths`、`Stream<ImageUploadFailure> get failures`；方法 `Future<void> pickAndUpload()`

**参照 `client/lib/cubits/voice_input_cubit.dart`。** 它是同一形状的兄弟：一次性事件走 broadcast 流（`transcripts`/`failures`），会话状态走 state 且无值相等（消费者用 `buildWhen`），`close()` 关掉两个流控制器。照它写，不要另发明。

`progress` 定义：`totalBytes == 0 ? 0 : sentBytes / totalBytes`。

- [ ] **Step 1: 写失败的测试**

`client/test/cubits/image_upload_cubit_test.dart`：

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/image_upload_cubit.dart';
import 'package:teampilot/services/pairing/pairing_upload_sender.dart';

void main() {
  late List<String> paths;
  late List<ImageUploadFailure> failures;
  late PickedImage? picked;
  late Object? uploadError;
  late int uploadCalls;
  late List<int> progressTicks;
  late String uploadedPath;
  late void Function(void Function(int, int)? onProgress)? driveProgress;

  ImageUploadCubit build({int maxBytes = 100}) {
    final cubit = ImageUploadCubit(
      maxBytes: maxBytes,
      pickImage: () async => picked,
      upload:
          ({
            required String filename,
            required Uint8List bytes,
            void Function(int sent, int total)? onProgress,
          }) async {
            uploadCalls++;
            final error = uploadError;
            if (error != null) throw error;
            driveProgress?.call(onProgress);
            return uploadedPath;
          },
    );
    cubit.paths.listen(paths.add);
    cubit.failures.listen(failures.add);
    return cubit;
  }

  setUp(() {
    paths = [];
    failures = [];
    uploadCalls = 0;
    progressTicks = [];
    uploadError = null;
    uploadedPath = '/home/dev/app/photo.jpg';
    driveProgress = null;
    picked = PickedImage(
      filename: 'photo.jpg',
      bytes: Uint8List.fromList(List.filled(10, 1)),
    );
  });

  test('starts idle with no progress', () {
    final cubit = build();
    expect(cubit.state.status, ImageUploadStatus.idle);
    expect(cubit.state.progress, 0);
    cubit.close();
  });

  test('emits the host path and returns to idle', () async {
    final cubit = build();
    await cubit.pickAndUpload();
    expect(paths, ['/home/dev/app/photo.jpg']);
    expect(cubit.state.status, ImageUploadStatus.idle);
    expect(failures, isEmpty);
    await cubit.close();
  });

  test('a cancelled pick uploads nothing and reports no failure', () async {
    // Backing out of the photo sheet is not an error.
    picked = null;
    final cubit = build();
    await cubit.pickAndUpload();
    expect(uploadCalls, 0);
    expect(failures, isEmpty);
    expect(cubit.state.status, ImageUploadStatus.idle);
    await cubit.close();
  });

  test('refuses an oversized image without a round trip', () async {
    // Checking locally means the user hears about it immediately instead of
    // after a wasted begin.
    picked = PickedImage(
      filename: 'huge.png',
      bytes: Uint8List.fromList(List.filled(101, 1)),
    );
    final cubit = build(maxBytes: 100);
    await cubit.pickAndUpload();
    expect(failures, [ImageUploadFailure.tooLarge]);
    expect(uploadCalls, 0);
    await cubit.close();
  });

  test('maps the host too_large code', () async {
    uploadError = const PairingUploadException('too_large');
    final cubit = build();
    await cubit.pickAndUpload();
    expect(failures, [ImageUploadFailure.tooLarge]);
    await cubit.close();
  });

  test('maps the host unsupported_type code', () async {
    uploadError = const PairingUploadException('unsupported_type');
    final cubit = build();
    await cubit.pickAndUpload();
    expect(failures, [ImageUploadFailure.unsupportedType]);
    await cubit.close();
  });

  test('maps every other host code to a generic failure', () async {
    for (final code in ['bad_filename', 'no_target', 'write_failed', 'weird']) {
      failures = [];
      uploadError = PairingUploadException(code);
      final cubit = build();
      await cubit.pickAndUpload();
      expect(failures, [ImageUploadFailure.failed], reason: code);
      await cubit.close();
    }
  });

  test('maps a non-protocol error to a generic failure and returns to idle',
      () async {
    uploadError = StateError('socket died');
    final cubit = build();
    await cubit.pickAndUpload();
    expect(failures, [ImageUploadFailure.failed]);
    expect(cubit.state.status, ImageUploadStatus.idle);
    await cubit.close();
  });

  test('tracks progress while uploading', () async {
    driveProgress = (onProgress) {
      onProgress?.call(4, 10);
      progressTicks.add(4);
      onProgress?.call(10, 10);
      progressTicks.add(10);
    };
    final cubit = build();
    await cubit.pickAndUpload();
    expect(progressTicks, [4, 10]);
    await cubit.close();
  });

  test('ignores a second request while one is in flight', () async {
    // One upload at a time; cancelling would need another protocol frame.
    final cubit = build();
    final first = cubit.pickAndUpload();
    await cubit.pickAndUpload();
    await first;
    expect(uploadCalls, 1);
    await cubit.close();
  });

  test('close does not emit after the cubit is gone', () async {
    final cubit = build();
    await cubit.close();
    await expectLater(cubit.pickAndUpload(), completes);
    expect(uploadCalls, 0);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd client && flutter test test/cubits/image_upload_cubit_test.dart
```

预期：`Target of URI doesn't exist: 'package:teampilot/cubits/image_upload_cubit.dart'`。

- [ ] **Step 3: 写 `image_upload_cubit.dart`**

要求，逐条照做：

- `paths` 与 `failures` 都是 `StreamController<T>.broadcast()`，`close()` 里关闭。文档注释照 `voice_input_cubit.dart` 里那段的理由写：一次性事件不进 state，否则每次进度都重画；也不做构造回调，因为消费者（镜像页、Composer）比 cubit 的创建时机晚。
- `pickAndUpload()`：
  1. `if (isClosed) return;` 与 `if (state.status != ImageUploadStatus.idle) return;`
  2. `emit(picking)` → `final image = await pickImage();` → `if (isClosed) return;` → `image == null` 则 `emit(idle)` 并 return（**取消不算失败**）
  3. 本地大小自查：`image.bytes.length > maxBytes` → 发 `ImageUploadFailure.tooLarge`、`emit(idle)`、return，**不调 upload**
  4. `emit(uploading, sentBytes: 0, totalBytes: image.bytes.length)`
  5. `try { final path = await upload(filename: …, bytes: …, onProgress: (sent, total) { if (!isClosed) emit(state.copyWith(sentBytes: sent, totalBytes: total)); }); if (!isClosed) { _paths.add(path); } }`
  6. `on PairingUploadException catch (e, st)` → 按 code 映射后发 failure，并 `AppLogger.instance.w('Image upload rejected: ${e.code}', error: e, stackTrace: st)`
  7. `on Object catch (e, st)` → 发 `ImageUploadFailure.failed` + `AppLogger.instance.w(...)`
  8. `finally { if (!isClosed) emit(const ImageUploadState.idle()); }` —— **状态必须先回 idle 再谈别的**，否则按钮永远转圈
- code 映射写成私有顶层函数 `ImageUploadFailure _failureForCode(String code)`，`switch` 带 `default` 归到 `failed`（这里要 `default`：宿主将来加新码时不该让手机编译失败）。
- 文件不超过 ~180 行。

- [ ] **Step 4: 跑测试确认通过**

```bash
cd client && flutter test test/cubits/image_upload_cubit_test.dart
```

预期：`All tests passed!`，12 个测试。

- [ ] **Step 5: analyze 并提交**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
git add \
  client/lib/cubits/image_upload_cubit.dart \
  client/test/cubits/image_upload_cubit_test.dart && \
git commit -m "feat: add ImageUploadCubit

Paths and failures leave on broadcast streams, matching VoiceInputCubit: a
path has to be written into a controller the mirror page owns, and a
failure has to raise a snack bar that may arrive after the panel unmounted.

The size check runs locally before begin so an oversized photo is refused
immediately instead of after a wasted round trip."
```

---

### Task 8: Composer 的 `+` 按钮与镜像页接线

**Files:**
- Modify: `client/lib/pages/pairing/mobile_toolbar/mobile_composer_panel.dart`
- Create: `client/lib/pages/pairing/mobile_toolbar/upload_failure_messenger.dart`
- Modify: `client/lib/pages/pairing/pairing_mirror_page.dart`
- Modify: `client/lib/utils/ui/app_keys.dart`
- Modify: `client/lib/l10n/app_en.arb`、`client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/pairing/composer_attach_button_test.dart`（新建）
- Test: `client/test/pages/pairing/mobile_composer_panel_test.dart`（**刻意改一条**，见 Step 6）
- Test: `client/test/pages/pairing/mobile_bottom_slot_test.dart`、`composer_mic_button_test.dart`（可能需补 provider，**断言不改**）

**Interfaces:**
- Consumes: `ImageUploadCubit`、`ImageUploadState`、`ImageUploadStatus`、`ImageUploadFailure`、`PickedImage`（Task 7）；`shellQuotePath`（Task 2）；`insertTranscript`（`lib/services/stt/transcript_insertion.dart`，C 期的纯函数）；`PairingClientCubit.uploadImage`（Task 6）。
- Produces: `AppKeys.mobileComposerAttachButton`；4 条 l10n 键。

**本任务的 l10n 键**（两个 ARB 都加）：

| key | en | zh |
|---|---|---|
| `mobileComposerAttach` | Attach image | 附加图片 |
| `imageUploadFailed` | Image upload failed | 图片上传失败 |
| `imageUploadTooLarge` | Image is larger than {mb} MB | 图片超过 {mb} MB |
| `imageUploadUnsupportedType` | That image type is not supported | 不支持该图片格式 |

`imageUploadTooLarge` 需 placeholder 元数据块，**只进模板文件 `app_en.arb`**：

```json
  "imageUploadTooLarge": "Image is larger than {mb} MB",
  "@imageUploadTooLarge": {
    "placeholders": {
      "mb": { "type": "int" }
    }
  },
```

- [ ] **Step 1: 加 l10n 与 app_keys，重新生成**

`app_keys.dart` 在 `mobileComposerMicButton` 那行之后加：

```dart
  static const mobileComposerAttachButton = Key('mobile-composer-attach');
```

```bash
cd client && flutter gen-l10n && dart run tool/gen_warmup_glyphs.dart
```

**先跑这一步再写引用新键的代码** —— 生成物落后于 ARB 已在 A、B、C 三期各浪费过一轮编译。用 `git status --short client/lib` 找生成物的真实路径，别照抄清单（C 期的 warmup glyphs 实际在 `lib/widgets/`，不在 `lib/theme/`）。

- [ ] **Step 2: 写 `upload_failure_messenger.dart`**

照 `client/lib/pages/pairing/mobile_toolbar/voice_failure_messenger.dart` 的形状写（先读它）：`StatefulWidget`，接 `Stream<ImageUploadFailure> failures` 与 `child`，`initState` 订阅，回调里判 `mounted` 后 `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)))`，`dispose` 取消订阅。

文案映射：`tooLarge` → `l10n.imageUploadTooLarge(maxMb)`、`unsupportedType` → `l10n.imageUploadUnsupportedType`、`failed` → `l10n.imageUploadFailed`。`maxMb` 作为构造参数传入（默认 25），这样上限只在一处定义。

类文档注释写明：用 widget 而非 `BlocListener`，因为失败是事件不是状态 —— 失败后 cubit 回 `idle`，与从未上传过无法区分。

- [ ] **Step 3: 改 `mobile_composer_panel.dart`**

先完整读它。按钮行当前的 children 顺序是：关闭 → `SizedBox(8)` → 收起键盘 → `SizedBox(8)` → 提交模式切换 → `Spacer()` → 麦克风（含 `Padding(right: 8)`）→ 发送。

1. **`+` 按钮插在提交模式切换与 `Spacer()` 之间**，前面补一个 `const SizedBox(width: 8)`。用独立的 `BlocBuilder<ImageUploadCubit, ImageUploadState>`，**不要动按钮行现有那个 `buildWhen: chatMode` 的 `BlocBuilder`**：

```dart
                    const SizedBox(width: 8),
                    BlocBuilder<ImageUploadCubit, ImageUploadState>(
                      // ImageUploadState has no value equality and progress
                      // emits on every ack, so this guard keeps the rest of the
                      // row out of the rebuild.
                      buildWhen: (before, after) =>
                          before.status != after.status ||
                          before.progress != after.progress,
                      builder: (context, upload) => _AttachButton(state: upload),
                    ),
```

2. 文件末尾新增私有 `_AttachButton extends StatelessWidget`，两态：

- `idle` → `_CircleButton(buttonKey: AppKeys.mobileComposerAttachButton, icon: Icons.add, tooltip: l10n.mobileComposerAttach, onTap: () => context.read<ImageUploadCubit>().pickAndUpload())`
- `picking` / `uploading` → 与 `_CircleButton` 同底色同圆角的 34px 容器，里面 `SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, value: state.status == ImageUploadStatus.uploading ? state.progress : null))`，无手势

`uploading` 用**确定**进度（`value:` 非 null）。仓里 pairing 下所有进度都是不确定转圈，这是有意偏离：字节数我们真的知道，有确定进度却显示不确定转圈是在丢信息。`picking` 期间还没有字节数，所以 `value: null`。

3. 面板最外层再包一层 `UploadFailureMessenger(failures: context.read<ImageUploadCubit>().failures, child: …)`。C 期的 `VoiceFailureMessenger` 已经在外面包了一层，两层叠放即可，不要合并成一个通用 messenger —— 两条流的文案映射不同，合并只会把类型擦掉。

- [ ] **Step 4: 改 `pairing_mirror_page.dart`**

先完整读它。当前它自建 `_toolbar`（`MobileToolbarCubit`）、持有 `_composerText`/`_composerFocus`、借用 `_voice`（`VoiceInputCubit`），并订阅 `_voice.transcripts` 写输入框。

1. `initState` 里在 `_toolbar` 之后建 cubit：

```dart
    _upload = ImageUploadCubit(
      pickImage: _pickImage,
      upload: cubit.uploadImage,
    );
    // The host decides the path; the phone never guesses it. Quote it so a cwd
    // containing a space still yields one shell argument.
    _uploadPaths = _upload.paths.listen((path) {
      _composerText.value = insertTranscript(
        _composerText.value,
        '${shellQuotePath(path)} ',
      );
    });
```

字段：`late final ImageUploadCubit _upload;`、`StreamSubscription<String>? _uploadPaths;`。

2. `_pickImage` 私有方法 —— `image_picker` 只在这里出现，cubit 保持可测：

```dart
  Future<PickedImage?> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return null;
    return PickedImage(
      filename: picked.name,
      bytes: await picked.readAsBytes(),
    );
  }
```

`XFile.name` 已是纯文件名，不含目录成分；宿主仍会独立校验，两道都要有。

3. `dispose` 的顺序：`_uploadPaths?.cancel()` 必须排在 `_composerText.dispose()` **之前**（在途路径不能写进已销毁的 controller），`_upload.close()` 与既有 `_toolbar.close()` 放在一起。照该文件既有 dispose 的注释风格写明为什么这个顺序要紧。

4. `build` 里底部的 `MultiBlocProvider` 再加一项 `BlocProvider.value(value: _upload)`。

- [ ] **Step 5: 写 `composer_attach_button_test.dart`**

照 `client/test/pages/pairing/composer_mic_button_test.dart` 的骨架（先读它）：挂 `MobileComposerPanel`，用 `MultiBlocProvider` 提供 `MobileToolbarCubit` + `VoiceInputCubit` + `ImageUploadCubit`，`MaterialApp` 带 `localizationsDelegates` / `supportedLocales` / `locale: const Locale('en')`。`ImageUploadCubit` 注入假 picker 与假 upload。

必须覆盖：

1. idle 时 `+` 按钮存在（按 `AppKeys.mobileComposerAttachButton`）。
2. 点它调到注入的 picker（断言调用计数）。
3. `uploading` 时渲染的是 `CircularProgressIndicator` 且其 `value` 非 null（确定进度），且 `+` 图标不在。
4. 上传成功后 `cubit.paths` 发出宿主给的那个路径。**本测试不断言输入框内容** —— 订阅 `paths` 并写入 controller 的是镜像页，而镜像页需要活的 `PairingClientCubit` 与终端引擎，在此挂不起来（同一理由让 B 期把 `MobileBottomSlot` 拆了出去）。在这里自己重现一遍「套引号再插入」等于测试实现被测逻辑，属自证。引用由 `shell_quote_test.dart` 保证，两者的组合由真机清单第 5 条保证。
5. 失败时弹出对应 snackbar：`tooLarge` 显示含 `25` 的文案，`unsupportedType` 与 `failed` 各自的文案。

- [ ] **Step 6: 刻意更新一条既有测试**

`client/test/pages/pairing/mobile_composer_panel_test.dart` 有一条 `renders the field and its four controls`，断言的是**精确控件数量**。面板现在合法地多了一个控件。

**把这条测试的名字与数量一起改成五个，并在测试内加一行注释说明 `+` 是第五个控件。** 这与「不许改既有断言」不冲突：那条规矩针对的是为了让新代码过关而放宽既有契约，而这里契约本身变了。提交信息里点名这条改动与原因。

其余测试文件若因 `ImageUploadCubit` 不在 scope 而报 `ProviderNotFoundException`（`mobile_bottom_slot_test.dart`、`composer_mic_button_test.dart`），只补 provider 包裹，**断言、测试名、既有注释一字不改**。

- [ ] **Step 7: 跑测试与全量 analyze**

```bash
cd client && flutter test test/pages/pairing/ test/cubits/
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

按钮行左组从三个变四个，加上右组的麦克风与发送共六个 34px 控件。**若有 widget 报 overflow，在实现里收紧间距，不要改测试画布尺寸** —— A 期有过第三个按钮把控件挤出 800pt 测试画布的先例，当时正确做法是把控件滚动进视野而非放宽断言。

- [ ] **Step 8: 跑全量测试并提交**

```bash
cd client && flutter test --exclude-tags integration
```

预期：除 `command_palette_overlay_test.dart` 与 `pty_launch_environment_test.dart` 两个既存失败外全绿。

```bash
cd /Users/yitouxiaomaolv/git/cmux && git add \
  client/lib/pages/pairing/mobile_toolbar/mobile_composer_panel.dart \
  client/lib/pages/pairing/mobile_toolbar/upload_failure_messenger.dart \
  client/lib/pages/pairing/pairing_mirror_page.dart \
  client/lib/utils/ui/app_keys.dart \
  client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/test/pages/pairing/composer_attach_button_test.dart \
  client/test/pages/pairing/mobile_composer_panel_test.dart && \
git commit -m "feat(pairing): add the composer attach button

Determinate progress, deliberately unlike every other spinner in the
pairing UI: here the byte count is known, and showing an indeterminate ring
would throw that away.

The inserted path is shell-quoted, without which any workspace whose cwd
contains a space would produce a command the user cannot run.

mobile_composer_panel_test's control-count assertion is updated from four
to five. The panel legitimately gained a control, so the contract itself
changed — this is not a weakened assertion."
```

生成的 l10n 产物与其余因 provider 补齐而改动的测试文件一并显式 `git add`，路径用 `git status --short` 查实，仍**不准** `git add -A`。

---

## 收尾

全部任务完成后：

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
```

然后交由 `superpowers:finishing-a-development-branch` 处理分支。

真机验证清单（自动化覆盖不到，但每条都能一眼看出坏没坏）：

1. 本机面板：选一张相册图 → 进度走满 → 输入框出现绝对路径 → 终端里 `ls` 能看到该文件。
2. **SSH 面板**：同上，文件出现在**远程主机**的 cwd 而非桌面本机。这一条是 runtime target 那条链唯一的真实证明。
3. WSL 面板：文件出现在发行版内的 cwd。
4. iPhone 拍的 HEIC 图：不被拒。
5. cwd 带空格的工作区：插入的路径带引号，直接回车可用。
6. 同名上传两次：第二次落成 `-1` 后缀，输入框里是实际路径。
7. 超过 25 MB 的图：立刻提示，不发起传输。
8. 上传进行中退出镜像页：桌面无残留文件，再次进入可正常上传。
