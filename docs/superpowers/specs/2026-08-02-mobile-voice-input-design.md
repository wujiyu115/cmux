# 移动端语音输入（子项目 C）

日期：2026-08-02
状态：设计已确认，待实现
参照：`/Users/yitouxiaomaolv/git/Nexterm`（`lib/features/terminal/services/stt/`、`ui/widgets/composer_panel.dart`、`lib/features/settings/ui/widgets/stt_settings_section.dart`）
前置：子项目 B 已合入 main（`docs/superpowers/specs/2026-08-01-mobile-composer-design.md`）

## 背景

B 给了移动端 pairing 镜像一个 Composer 多行文本面板：先在本地编辑好，再一次性发给宿主 PTY。它的按钮行里留了一个 `Spacer()`，语音与附件各占其一。

手机上打字本来就慢，往 agent CLI（Claude Code 一类）里输入整段提示词更慢。语音输入把口述转成文本落进 Composer，由人过目后再发送。

## 目标

1. Composer 按钮行新增麦克风按钮，点按开始、再点按结束，识别文本插入输入框光标处。
2. 三个识别后端：系统识别（`speech_to_text`）、火山引擎豆包（WebSocket）、阿里云 NLS（WebSocket）。运行时可切换。
3. 云端凭据存入系统钥匙串，非机密偏好（provider、语言）存 `SharedPreferences`。
4. 手机可达的语音设置页：provider 选择、语言选择、凭据编辑、连接测试。
5. 音频上云这一事实对用户明示。

### 非目标

- **附件 `+` 按钮**（子项目 D）。
- **桌面端**。Composer 只存在于手机 pairing 镜像页（`PairingMirrorPage` 仅由 `pairing_mobile_shell.dart:122` 实例化，而该 shell 仅在 `isPairingClient` 时挂载）。做桌面等于做死 UI。
- **长按说话模式**。Nexterm 把「点按切换 / 长按说话」做成设置项，两套状态机。本项目只做点按切换：长按手势留给「长按麦克风进设置页」。
- **实时 partial 覆写输入框**。只在 final 结果时插入。每个中间结果重写 `TextEditingController` 会与软键盘 IME 争抢，并吞掉用户手动改动。
- **客户端 VAD / 静音检测**。阿里服务端 `max_sentence_silence: 800` 保留，不自研。
- **键条上的麦克风**。语音必然误识别，结果必须先落进可编辑框由人过目。键条按键直通 PTY，语音直通 PTY 等于让识别错误直接在 shell 里执行。
- **`permission_handler` 依赖**。`record.hasPermission()` 与 `speech_to_text.initialize()` 各自会拉系统弹窗，够用。代价是权限被永久拒绝后无法从 app 内跳系统设置，只能文字告知。
- **提示词/命令历史、音频留存**。音频不落盘，不缓存。

## 架构

### 状态归属

新建 `VoiceInputCubit`，**不折进 `MobileToolbarCubit`**。后者已 ~300 行，管键位布局、持久化、修饰键、面板模式；再塞进音频流生命周期、provider 选择、权限态、错误态会顶穿 AGENTS.md 的 cubit ~500 行软上限，且两者生命周期不同：工具栏状态跟页面活，录音会话短命且可失败。

provider 选择、凭据、可用性要与设置页共享，故必须进 cubit（AGENTS.md：state 只用 `flutter_bloc`），排除「纯 service + `setState`」。

```dart
enum SttProviderType { system, volcengine, aliyun }

enum VoiceInputStatus { idle, starting, listening }

class VoiceInputState {
  final SttProviderType provider;   // 默认 system，持久化
  final String localeId;            // 空串 = 跟随系统，持久化
  final VoiceInputStatus status;    // 不持久化
  final bool available;             // 派生：见下
  final bool configured;            // 所选 provider 凭据是否齐备
}
```

`available` 语义：**任一 provider 可用** —— system 的 `initialize()` 成功，或某朵云凭据齐备。只有「这台设备上语音输入完全无从可用」才为假。为假时隐藏麦克风按钮，但 `mobile_settings_sheet` 的入口行始终在，不会锁死配置。

`available` 与 `configured` 是两回事：麦克风可见（`available`）但所选 provider 没凭据（`!configured`）时，按钮照样渲染，tap 推设置页 —— 见「错误处理」。

`configured`：system 恒真；volcengine 需 `appId` + `accessToken`；aliyun 需 `accessKeyId` + `accessKeySecret` + `appKey`。

Cubit 公开方法：

```dart
Future<void> load();
Future<void> startListening();
Future<void> stopListening();
Future<void> setProvider(SttProviderType type);
Future<void> setLocaleId(String localeId);
Future<int> testConnection();        // 返回毫秒；失败抛异常
```

### 识别文本如何进输入框

Cubit 构造时注入回调，与 A/B 期 `sendInput` 注入同构：

```dart
VoiceInputCubit({
  required VoiceInputRepository repository,
  required SttProvider Function(SttProviderType) providerFactory,
  required void Function(String text) onTranscript,
  Duration maxDuration = const Duration(seconds: 60),
});
```

镜像页传闭包，写自己持有的 `_composerText`（B 期已由 `_PairingMirrorPageState` 持有并 `dispose`）。Cubit 不认识 widget，纯 Dart 可测。

**文本不进 cubit state** —— 与 B 期同一理由：否则每条结果 emit 一次。

插入逻辑抽成纯函数：

```dart
// lib/services/stt/transcript_insertion.dart
TextEditingValue insertTranscript(TextEditingValue value, String text);
```

替换当前选区，插入后光标折叠到插入内容之后。**刻意不照抄 Nexterm**：它的 `_insertText` 直接 `text.replaceRange(selection.start, selection.end, text)`，而输入框从未获焦时 `selection` 是 `TextSelection.collapsed(offset: -1)`，`replaceRange(-1, -1, …)` 抛 `RangeError`。本实现在 `offset < 0` 时追加到文本末尾。`text` 为空时原样返回。

### 文件

| 文件 | 职责 |
|---|---|
| `lib/services/stt/stt_provider.dart`（新建，~60 行） | `abstract SttProvider`、`SttResult`、`SttProviderType`、`SttChannelFactory` typedef、`VoicePermissionDeniedException`、`SttException`。零 IO。 |
| `lib/services/stt/transcript_insertion.dart`（新建，~30 行） | 纯函数 `insertTranscript`。零 import（除 flutter 的 `TextEditingValue`）。 |
| `lib/services/stt/system_stt_provider.dart`（新建，~80 行） | `speech_to_text` 包封装。 |
| `lib/services/stt/volcengine_frame_codec.dart`（新建，~120 行） | 纯二进制封帧/解帧。零 socket 依赖。 |
| `lib/services/stt/volcengine_stt_provider.dart`（新建，~180 行） | 豆包 WebSocket 会话。 |
| `lib/services/stt/aliyun_signature.dart`（新建，~60 行） | 纯 HMAC-SHA1 签名 + percent-encode。 |
| `lib/services/stt/aliyun_token_service.dart`（新建，~90 行） | `CreateToken` RPC + 按 `ExpireTime` 缓存。 |
| `lib/services/stt/aliyun_stt_provider.dart`（新建，~180 行） | 阿里 NLS WebSocket 会话。 |
| `lib/services/stt/audio_recorder_service.dart`（新建，~60 行） | `record` 包 → `Stream<Uint8List>` PCM16/16k/mono。 |
| `lib/services/stt/stt_locales.dart`（新建，~50 行） | 各 provider 的语言列表。 |
| `lib/repositories/voice_input_repository.dart`（新建，~120 行） | 偏好走 `SharedPreferences`，凭据走既有 `SecureKeyValueStore`。 |
| `lib/repositories/ssh_credential_store.dart`（改，+~20 行） | 新增 `InMemorySecureKeyValueStore` 供测试，与既有 `InMemorySshCredentialStore` 同层。 |
| `lib/cubits/voice_input_cubit.dart`（新建，~220 行） | 状态与会话编排。 |
| `lib/pages/pairing/voice/voice_settings_page.dart`（新建，~220 行） | 全页设置。 |
| `lib/pages/pairing/mobile_toolbar/mobile_composer_panel.dart`（改，+~70 行） | 麦克风按钮与三态。 |
| `lib/pages/pairing/pairing_mirror_page.dart`（改，+~20 行） | 创建/关闭 `VoiceInputCubit`，注入 `onTranscript`。 |
| `lib/pages/pairing/mobile_settings_sheet.dart`（改，+~15 行） | 语音设置入口行。 |
| `lib/utils/ui/app_keys.dart`（改） | 测试键。 |
| `lib/l10n/app_en.arb` / `app_zh.arb`（改） | 24 条文案。 |
| `client/pubspec.yaml`（改） | 两个新依赖 + 一个 override。 |
| `client/ios/Runner/Info.plist`（改） | 两条权限说明。 |
| `client/android/app/src/main/AndroidManifest.xml`（改） | `RECORD_AUDIO` + `<queries>`。 |

### 依赖

```yaml
speech_to_text: ^7.0.0
record: 5.1.0            # 精确锁版，与 Nexterm 一致

dependency_overrides:
  record_platform_interface: 1.1.0
```

已在仓内、本次首次或复用：`web_socket_channel: ^2.4.0`（已声明但 `client/lib` 全仓未用；豆包需自定义 header，走 `IOWebSocketChannel.connect(url, headers: …)`）、`crypto: ^3.0.7`（阿里签名需 `Hmac`，仓内目前只用 `sha256`）、`http: ^1.6.0`（阿里 token RPC；仓内无 `dio`）、`flutter_secure_storage: ^10.2.0`、`uuid: ^4.5.1`（豆包 `X-Api-Request-Id`）。

### 平台权限

iOS `client/ios/Runner/Info.plist` 新增：

| key | 值 |
|---|---|
| `NSMicrophoneUsageDescription` | `TeamPilot uses the microphone for voice input in the terminal composer.` |
| `NSSpeechRecognitionUsageDescription` | `TeamPilot uses speech recognition to turn your voice into terminal input.` |

Android `client/android/app/src/main/AndroidManifest.xml` 新增：

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<queries>
  <intent>
    <action android:name="android.speech.RecognitionService"/>
  </intent>
</queries>
```

`<queries>` 是 Android 11+ 让 `speech_to_text` 能发现系统识别服务的必需项，缺了会表现为 `initialize()` 返回 false。

## Provider 协议细节

### 接口

```dart
class SttResult {
  const SttResult({required this.text, required this.isFinal});
  final String text;
  final bool isFinal;
}

abstract class SttProvider {
  Future<bool> isAvailable();
  Stream<SttResult> start({String? localeId});
  Future<void> stop();
  Future<int> testConnection();   // 毫秒；失败抛异常
  void dispose();
}
```

云端两个 provider 的构造函数注入连接工厂，测试可塞假 channel：

```dart
typedef SttChannelFactory =
    WebSocketChannel Function(Uri url, {Map<String, dynamic>? headers});
```

### 系统识别

`speech_to_text` 包。`isAvailable()` = `SpeechToText().initialize()`。`start` 调
`listen(onResult:…, listenOptions: SpeechListenOptions(listenMode: ListenMode.dictation, cancelOnError: true, localeId: localeId))`；`isFinal` 取 `result.finalResult`。`testConnection()` 返回 0（本地识别无连接可测，设置页对 system 隐藏测试按钮）。不使用 `AudioRecorderService`，麦克风由该插件自管。

### 火山引擎豆包

- WebSocket：`wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream`
- header：`X-Api-App-Key`=appId、`X-Api-Access-Key`=accessToken、`X-Api-Resource-Id`=`volc.seedasr.sauc.duration`、`X-Api-Request-Id`=uuid v4
- 自定义二进制封帧：4 字节头 —— `byte0 = 0x11`（协议版本 1，header size 1）、`byte1 = messageType << 4 | flags`、`byte2 = serialization << 4 | compression`、`byte3 = 0`；随后 int32 big-endian 序号 + uint32 big-endian payload 长度 + payload
- 配置帧 `messageType 0x01`，payload 为 gzip 压缩的 JSON；音频帧 `messageType 0x02`，payload 为 gzip 压缩的裸 PCM；末包序号取负、flags `0x03`
- 服务端帧：`0x09` 结果、`0x0F` 错误
- 配置 JSON：`audio {format:'pcm', rate:16000, bits:16, channel:1, language: localeId ?? 'zh-CN'}`、`request {model_name:'bigmodel', enable_itn:true, enable_punc:true, result_type:'full', show_utterances:true}`
- `isFinal = isLast || utterances.last['definite'] == true`
- `testConnection()`：发 1 秒静音 PCM，计到首个 `0x09` 的毫秒，10 秒超时
- `stop()` 后等 3 秒收尾

### 阿里云 NLS

两段式鉴权。先 HTTP RPC 取 token：

- `https://nls-meta.cn-shanghai.aliyuncs.com/`，`Action=CreateToken`、`Version=2019-02-28`
- 签名 HMAC-SHA1，签名键为 `accessKeySecret + '&'`，`SignatureMethod=HMAC-SHA1`
- 自定义 percent-encode：在 `Uri.encodeComponent` 之上，把 `+` 换成 `%20`、`*` 换成 `%2A`、`%7E` 还原为 `~`
- 按响应 `ExpireTime` 缓存 token

再连 WebSocket：

- `wss://nls-gateway-cn-shanghai.aliyuncs.com/ws/v1?token=$token`
- JSON 消息，`header {appkey, message_id, task_id, namespace:'SpeechTranscriber', name}`；`message_id`/`task_id` 为 32 位随机 hex
- `StartTranscription` payload：`{format:'pcm', sample_rate:16000, enable_intermediate_result:true, enable_punctuation_prediction:true, enable_inverse_text_normalization:true, max_sentence_silence:800}`
- **收到 `TranscriptionStarted` 之后才可发送裸二进制 PCM**。早发音频会被服务端丢任务，是这类实现的经典坑，必须有测试钉住
- 结果事件：`TranscriptionResultChanged` → partial、`SentenceEnd` → final、`TranscriptionCompleted` / `TaskFailed`
- `testConnection()`：计到 `TranscriptionStarted` 的毫秒，10 秒超时
- `stop()` 发 `StopTranscription` 后等 2 秒收尾

### 音频采集

`AudioRecorderService` 用 `record` 包：`hasPermission()` → `startStream(RecordConfig(encoder: AudioEncoder.pcm16bits, numChannels: 1, sampleRate: 16000))`，把 `Uint8List` 块经 broadcast `StreamController` 转发。不设块大小，由插件驱动。权限被拒时 `start()` 抛 `VoicePermissionDeniedException`，由 cubit 转成 snackbar。

### 标点与 ITN

云端 `enable_punc` 与 `enable_itn` 均保持开启（同 Nexterm）。给 shell 命令加标点是负分，但本 Composer 主用途是往 agent CLI 里口述整段话，标点是正分；且文本落在可编辑框内，多一个逗号删掉即可，缺标点却要手打。ITN 把「十六」转成 `16`，两种用途都受益。

## 存储

| 数据 | 位置 | 键 |
|---|---|---|
| provider、localeId | `SharedPreferences` 单键 JSON，照 `SessionPreferencesRepository` 的 load/save 惯例 | `teampilot.voice_input.v1` |
| 豆包 appId / accessToken | 既有 `SecureKeyValueStore`（`ssh_credential_store.dart:14`） | `teampilot.voice_creds.v1.volc_app_id` / `.volc_access_token` |
| 阿里 accessKeyId / accessKeySecret / appKey | 同上 | `teampilot.voice_creds.v1.aliyun_access_key_id` / `.aliyun_access_key_secret` / `.aliyun_app_key` |

`SecureKeyValueStore` 是已有抽象（`read`/`write`/`delete`），`FlutterSecureKeyValueStore` 已处理 macOS 钥匙串的 `usesDataProtectionKeychain: false` 变通。仓库层再提供 `InMemorySecureKeyValueStore` 供测试（`ssh_credential_store.dart` 已有 `InMemorySshCredentialStore` 先例，按同样思路给 KV 层加一个即可）。

坏 JSON 用 `AppLogger` 记 `FormatException` 后回落默认值，与 `SharedPrefsMobileToolbarRepository`（A 期）一致。

## UI

### 麦克风按钮

位置：Composer 按钮行 `Spacer()`（`mobile_composer_panel.dart:142`）与发送键之间。沿用该文件私有 `_CircleButton`（`TpIconButton`，`size: 34`、`iconSize: 18`、`borderRadius: 17`）。`available` 为假时不渲染。

| 状态 | 表现 |
|---|---|
| `idle` | `Icons.mic_none`，`cs.surfaceContainerHighest` 底 / `cs.onSurfaceVariant` 图标 |
| `starting` | 18pt `CircularProgressIndicator`，`onTap: null` |
| `listening` | `Icons.mic`，`cs.primary` 底 / `cs.onPrimary` 图标，外加外扩脉冲环：`AnimationController` repeat，scale 1.0→1.8、opacity 0.4→0 |

`starting` 是对 Nexterm 的必要补充：阿里要先 HTTP 取 token 再 WS 握手，真机上 1~2 秒空窗，Nexterm 那里点下去毫无反馈。

角标沿用 Nexterm 的 provider 标签思路，按钮右上角小字。但 Nexterm 把 `'SYS'` / `'豆包'` / `'ALI'` 硬编码在 widget 里 —— AGENTS.md 要求所有用户可见文案走 l10n，故取三条独立短键 `voiceInputBadgeSystem` / `Volcengine` / `Aliyun`，不复用较长的 provider 名。

无波形/电平表（Nexterm 也没有，只有装饰性脉冲环）。

交互：`onTap` 切换。`onLongPress` 推语音设置页。

### 必停时机

四条路径都要 `stopListening()`：Composer 关闭按钮、`mode` 切回 `keys`、镜像页 `dispose`、`PopScope` 退出镜像。麦克风留在开着是隐私问题，不是体验问题。

### 设置页

`pages/pairing/voice/voice_settings_page.dart`，`Navigator.push` 全页，照 `MobileToolbarCustomizePage.route()`（`mobile_toolbar_customize_page.dart:21`）的静态 `route()` 写法。

两个入口：`mobile_settings_sheet` 新增一行；长按麦克风。

自上而下：

1. provider 三选一（`RadioListTile` × 3）
2. 语言选择行 → 推列表页/对话框。system 走 `SpeechToText().locales()`（失败回落内置表），两个云端用 `stt_locales.dart` 硬编码表。空串显示为「跟随系统」
3. 按所选 provider 条件显示凭据字段。豆包 2 个，阿里 3 个。`accessToken` / `accessKeySecret` 用 `obscureText: true`
4. 连接测试按钮（system 时隐藏）
5. 云端 provider 时常驻隐私说明行 `voiceInputCloudPrivacyNote`

凭据字段照 `session_config_section.dart` 的表单惯例：`TextEditingController` + `Debouncer`（`lib/utils/debounce/debounce.dart`）+ `onSubmitted` 立即落盘。

## 隐私边界

cmux 的 pairing 通道是 E2EE。语音走云端时，**音频直接从手机发往字节/阿里，不经过 pairing 通道**，只有识别出的文本才进 E2EE 链路。这绕过了本项目对外宣称的信任边界，用户有权在开启前知道，故设置页常驻说明行。iOS 的系统识别也可能走 Apple 服务器，同样计入该说明。

音频不落盘、不缓存、不经宿主。

## 错误处理

| 情形 | 响应 |
|---|---|
| 所选 provider 未配置凭据（`configured == false`） | 直接推语音设置页。动作本身就是修复 |
| 麦克风权限被拒 | snackbar `voiceInputPermissionDenied`。无系统设置深链，文字告知 |
| 运行时失败（WS 断开 / token 失败 / 网络 / 识别器异常） | snackbar `voiceInputFailed` + `AppLogger.error` 记细节，状态回 `idle` |
| 60 秒到点 | 静默自动 `stopListening()`，已识别文本保留，不提示 |

snackbar 照仓内惯例：`ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.key)))`（`pairing_config_section.dart:170`）。

超时：连接测试 10 秒；`stop()` 后豆包等 3 秒、阿里等 2 秒收尾。

**60 秒硬上限**是对 Nexterm 的补充（它无任何上限）。口述一条命令或一段提示词不会到 60 秒；忘关的麦克风在计费的云端 STT 上是真实成本，也是隐私敞口。

## 已知副作用

- 云端识别期间持续上行音频（16kHz/16bit/单声道 ≈ 32 KB/s）。移动网络下计流量，由用户自担。
- 麦克风占用期间，同设备其他录音应用会被系统打断。
- Composer 高度不因麦克风按钮变化，不触发额外的 PTY reflow（按钮行高度未变）。

## 测试

不碰真网络、不碰真麦克风。全部构造函数注入。

### 纯函数 golden test

- `volcengine_frame_codec_test.dart`：`0x11` 头字节、`messageType << 4 | flags` 组合、int32 big-endian 序号、uint32 payload 长度、gzip 往返、末包负序号 + flags `0x03`；解析 `0x09` 结果帧与 `0x0F` 错误帧。
- `aliyun_signature_test.dart`：固定向量比对 —— 参数字典序、`~` / `*` / 空格的 percent-encode、签名键 `secret + '&'`、HMAC-SHA1 base64 结果。
- `transcript_insertion_test.dart`：折叠光标插入、替换选区、`offset == -1` 追加到末尾、空文本原样返回、连续多次插入累积。

### cubit test（假 provider + 假 recorder）

`start`/`stop` 往复；仅 `isFinal` 时调 `onTranscript`；流 `onDone` 时若无 final 则补插最后一条 partial；错误回 `idle` 且上报；`setProvider` 重算 `available` / `configured`；无凭据时 `configured` 为假；60 秒到点自动停（`fake_async`）；`close()` 时必停。

`bloc_test` 不加（仓内无此依赖）；`fake_async` 已有。

### provider test（注入假 channel）

- 豆包：配置帧 → 音频帧 → 末包，顺序与序号正确；`0x0F` 错误帧转成异常。
- 阿里：**`TranscriptionStarted` 之前不发送任何 PCM**；`TranscriptionResultChanged` → partial、`SentenceEnd` → final；token 按 `ExpireTime` 缓存，过期重取。

### widget test

按 `available` 渲染/隐藏麦克风；tap 调 `startListening`；`listening` 态图标为 `Icons.mic` 且填充；`starting` 态不可点；未配置时 tap 推设置页；设置页按 provider 显示对应字段数量并落盘；长按麦克风推设置页。

渲染本地化 UI 按 AGENTS.md 包 `AppLocalizations.localizationsDelegates` + `supportedLocales` + `locale: Locale('en')`。

## l10n

`app_en.arb` / `app_zh.arb` 各加 24 条。仅 `voiceInputTestPassed` 带 `@` placeholder 块。

| key | en | zh |
|---|---|---|
| `voiceInputStart` | Start dictation | 开始语音输入 |
| `voiceInputStop` | Stop dictation | 停止语音输入 |
| `voiceInputSettings` | Voice input | 语音输入 |
| `voiceInputProvider` | Recognition service | 识别服务 |
| `voiceInputProviderSystem` | System | 系统 |
| `voiceInputProviderVolcengine` | Doubao (Volcengine) | 豆包（火山引擎） |
| `voiceInputProviderAliyun` | Alibaba Cloud NLS | 阿里云智能语音 |
| `voiceInputLanguage` | Language | 识别语言 |
| `voiceInputLanguageDefault` | System default | 跟随系统 |
| `voiceInputCredentials` | Credentials | 凭据 |
| `voiceInputVolcAppId` | App ID | App ID |
| `voiceInputVolcAccessToken` | Access token | Access Token |
| `voiceInputAliyunAccessKeyId` | AccessKey ID | AccessKey ID |
| `voiceInputAliyunAccessKeySecret` | AccessKey secret | AccessKey Secret |
| `voiceInputAliyunAppKey` | App key | App Key |
| `voiceInputTestConnection` | Test connection | 测试连接 |
| `voiceInputTestPassed` | Connected in {ms} ms | 连接成功，耗时 {ms} 毫秒 |
| `voiceInputTestFailed` | Connection failed | 连接失败 |
| `voiceInputPermissionDenied` | Microphone access denied. Enable it in system settings. | 麦克风权限被拒绝，请在系统设置中开启 |
| `voiceInputFailed` | Voice input failed | 语音输入失败 |
| `voiceInputCloudPrivacyNote` | Audio is sent directly to the cloud provider, not through the encrypted pairing channel. | 音频将直接发送给云服务商，不经过端到端加密的配对通道。 |
| `voiceInputBadgeSystem` | SYS | 系统 |
| `voiceInputBadgeVolcengine` | DOU | 豆包 |
| `voiceInputBadgeAliyun` | ALI | 阿里 |

改完跑 `dart run tool/gen_warmup_glyphs.dart`；若生成的 `AppLocalizations` 落后于 ARB，跑 `flutter gen-l10n`（A、B 期各遇一次）。
