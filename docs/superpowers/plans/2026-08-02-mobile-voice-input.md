# 移动端语音输入 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 移动端 pairing 镜像的 Composer 面板新增麦克风按钮，口述内容经三个可切换的识别后端转成文本，插入输入框光标处由用户过目后发送。

**Architecture:** 一个 `abstract SttProvider` 接口后面挂三个实现：系统识别（`speech_to_text`）、火山引擎豆包（WebSocket + 自定义二进制封帧）、阿里云 NLS（WebSocket + JSON，两段式 AK/SK→token 鉴权）。`VoiceInputCubit` 活在 pairing shell 层、编排会话与持久化；识别文本经它的 broadcast 流由镜像页写进自己持有的 `TextEditingController`，不进 cubit state。协议封帧、签名、文本插入三处抽成纯函数，用 golden test 覆盖；两个云 provider 的 WebSocket 连接与音频采集全部构造函数注入，测试塞假实现，不碰真网络真麦克风。

**Tech Stack:** Flutter / `flutter_bloc` / `speech_to_text ^7.0.0` / `record 5.1.0` / `web_socket_channel ^2.4.0` / `crypto ^3.0.7` / `http ^1.6.0` / `flutter_secure_storage ^10.2.0`

Spec：`docs/superpowers/specs/2026-08-02-mobile-voice-input-design.md`
参照实现：`/Users/yitouxiaomaolv/git/Nexterm/nexterm/lib/features/terminal/services/stt/`

## Global Constraints

- 工作目录 `client/`。完成前必跑 `flutter analyze --no-fatal-infos --no-fatal-warnings` 与 `flutter test --exclude-tags integration`。
- **绝不 `git add -A` 或 `git add .`**。仓内有一批与本项目无关的未提交文件（`client/ios/Flutter/*.xcconfig`、`client/ios/Runner.xcodeproj/project.pbxproj`、`client/ios/Runner.xcworkspace/contents.xcworkspacedata`、`client/ios/Podfile`、`client/ios/Podfile.lock`，以及 `client/packages/` 各 submodule 内的同类产物）。每次提交显式列出本任务的文件。
- **两个既存失败的测试文件不准碰、不准"修"**：`test/pages/command_palette_overlay_test.dart`、`test/services/pty_launch_environment_test.dart`。它们在本分支基线上就是失败的。
- 状态管理只用 `flutter_bloc`，不用 `provider`，不用 `setState` 管共享状态。
- **`bloc_test` 不是本仓依赖，不准加**。`fake_async` 已有，测时间用它。
- 所有用户可见文案必须 l10n：`lib/l10n/app_en.arb` 与 `lib/l10n/app_zh.arb` **两个文件都要加**，经 `context.l10n.<key>` 使用。ARB 改完跑 `dart run tool/gen_warmup_glyphs.dart`；若生成的 `AppLocalizations` 落后于 ARB，跑 `flutter gen-l10n`。
- 不准用 `print`。诊断日志用 `AppLogger.instance.w(msg, error: e, stackTrace: st)`（`lib/utils/logging/logger_utils.dart`）。
- 测试中的子进程/文件系统/网络/麦克风一律构造函数注入，禁止真实 IO。
- 渲染本地化 UI 的 widget test 必须给 `MaterialApp` 传 `localizationsDelegates: AppLocalizations.localizationsDelegates`、`supportedLocales: AppLocalizations.supportedLocales`、`locale: const Locale('en')`。
- 文件大小软上限：cubit ~500 行、service ~600 行、page shell ~400 行。
- **不引入 `permission_handler`**。麦克风权限由 `record.hasPermission()` 与 `speech_to_text.initialize()` 各自拉起系统弹窗。
- 云端 `enable_punc` 与 `enable_itn` 保持 `true`（spec 已定，勿"优化"成 false）。
- 音频只从手机直发云服务商，**不经过 pairing 通道**，不落盘、不缓存。
- 麦克风必停的四条路径：Composer 关闭按钮、`mode` 切回 `keys`、镜像页 `dispose`、`PopScope` 退出镜像。
- 60 秒录音硬上限（`VoiceInputCubit` 的 `maxDuration` 构造参数，默认 `Duration(seconds: 60)`）。

---

## File Structure

| 文件 | 职责 | 任务 |
|---|---|---|
| `lib/services/stt/stt_provider.dart` | `SttProviderType`、`SttResult`、`abstract SttProvider`、`abstract SttSocket`、`SttSocketFactory`、`VoicePermissionDeniedException`、`SttException` | 1 |
| `lib/services/stt/stt_socket.dart` | `WebSocketSttSocket` —— `SttSocket` 的真实实现，包 `IOWebSocketChannel` | 5 |
| `lib/services/stt/transcript_insertion.dart` | 纯函数 `insertTranscript` | 1 |
| `lib/services/stt/volcengine_frame_codec.dart` | 豆包二进制封帧/解帧，纯函数 | 2 |
| `lib/services/stt/aliyun_signature.dart` | 阿里 RPC 签名，纯函数 | 3 |
| `lib/services/stt/aliyun_token_service.dart` | `CreateToken` + 按 `ExpireTime` 缓存 | 3 |
| `lib/services/stt/pcm_audio_source.dart` | `abstract PcmAudioSource` + `RecordPcmAudioSource`（`record` 包） | 4 |
| `lib/services/stt/speech_recognizer.dart` | `abstract SpeechRecognizer` + `PluginSpeechRecognizer`（`speech_to_text` 包） | 4 |
| `lib/services/stt/system_stt_provider.dart` | 系统识别 provider | 4 |
| `lib/services/stt/volcengine_stt_provider.dart` | 豆包 WebSocket 会话 | 5 |
| `lib/services/stt/aliyun_stt_provider.dart` | 阿里 NLS WebSocket 会话 | 6 |
| `lib/services/stt/stt_locales.dart` | 各 provider 语言列表 | 7 |
| `lib/repositories/voice_input_repository.dart` | 偏好（`SharedPreferences`）+ 凭据（`SecureKeyValueStore`） | 7 |
| `lib/repositories/ssh_credential_store.dart` | 追加 `InMemorySecureKeyValueStore` | 7 |
| `lib/cubits/voice_input_cubit.dart` | 状态与会话编排 | 8 |
| `lib/pages/pairing/mobile_toolbar/mobile_composer_panel.dart` | 麦克风按钮三态 | 9 |
| `lib/pages/pairing/pairing_mobile_shell.dart` | 提供 `VoiceInputCubit`（跨屏，设置入口在主屏） | 9 |
| `lib/pages/pairing/pairing_mirror_page.dart` | 订阅 `transcripts` 写入 Composer controller；四条必停路径 | 9 |
| `lib/pages/pairing/mobile_toolbar/voice_failure_messenger.dart` | 失败流 → snackbar | 9 |
| `lib/services/stt/stt_provider_factory.dart` | `buildSttProvider`，把真实插件/socket 接上 | 9 |
| `lib/pages/pairing/voice/voice_settings_page.dart` | 全页设置 | 10 |
| `lib/pages/pairing/mobile_settings_sheet.dart` | 语音设置入口行 | 10 |
| `lib/utils/ui/app_keys.dart` | 测试键 | 9、10 |
| `lib/l10n/app_en.arb` / `app_zh.arb` | 24 条文案 | 9、10 |
| `pubspec.yaml` | 两个新依赖 + 一个 override | 4 |
| `ios/Runner/Info.plist`、`android/app/src/main/AndroidManifest.xml` | 权限 | 4 |

任务依赖：1 → 2、3、4 → 5（需 2、4）、6（需 3、4）→ 7 → 8（需 1、7 及 4 的 provider 工厂）→ 9 → 10。

---

### Task 1: STT 接口与文本插入纯函数

**Files:**
- Create: `client/lib/services/stt/stt_provider.dart`
- Create: `client/lib/services/stt/transcript_insertion.dart`
- Test: `client/test/services/stt/transcript_insertion_test.dart`

**Interfaces:**
- Consumes: 无。
- Produces:
  - `enum SttProviderType { system, volcengine, aliyun }`
  - `class SttResult { const SttResult({required String text, required bool isFinal}); final String text; final bool isFinal; }`
  - `abstract class SttProvider` — `Future<bool> isAvailable()`、`Stream<SttResult> start({String? localeId})`、`Future<bool> get ready`、`Future<void> stop()`、`Future<int> testConnection()`、`void dispose()`
  - `abstract class SttSocket` — `Stream<dynamic> get messages`、`void send(Object data)`、`Future<void> close()`
  - `typedef SttSocketFactory = Future<SttSocket> Function(Uri url, {Map<String, String>? headers})`
  - `class VoicePermissionDeniedException implements Exception`
  - `class SttException implements Exception { const SttException(String message); final String message; }`
  - `TextEditingValue insertTranscript(TextEditingValue value, String text)`

- [ ] **Step 1: 写失败的测试**

`client/test/services/stt/transcript_insertion_test.dart`：

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/stt/transcript_insertion.dart';

void main() {
  test('appends when the field has never been focused', () {
    // A TextField that never took focus reports offset -1. Nexterm's port of
    // this calls text.replaceRange(-1, -1, …) here and throws RangeError.
    const value = TextEditingValue(
      text: 'ls',
      selection: TextSelection.collapsed(offset: -1),
    );
    final result = insertTranscript(value, ' -la');
    expect(result.text, 'ls -la');
    expect(result.selection, const TextSelection.collapsed(offset: 6));
  });

  test('inserts at a collapsed caret', () {
    const value = TextEditingValue(
      text: 'ls -la',
      selection: TextSelection.collapsed(offset: 2),
    );
    final result = insertTranscript(value, ' -h');
    expect(result.text, 'ls -h -la');
    expect(result.selection, const TextSelection.collapsed(offset: 5));
  });

  test('replaces the selection', () {
    const value = TextEditingValue(
      text: 'git commit',
      selection: TextSelection(baseOffset: 4, extentOffset: 10),
    );
    final result = insertTranscript(value, 'push');
    expect(result.text, 'git push');
    expect(result.selection, const TextSelection.collapsed(offset: 8));
  });

  test('replaces a reversed selection', () {
    // Dragging right-to-left leaves base > extent; start/end must be used, not
    // base/extent.
    const value = TextEditingValue(
      text: 'git commit',
      selection: TextSelection(baseOffset: 10, extentOffset: 4),
    );
    final result = insertTranscript(value, 'push');
    expect(result.text, 'git push');
    expect(result.selection, const TextSelection.collapsed(offset: 8));
  });

  test('returns the value unchanged for empty text', () {
    const value = TextEditingValue(
      text: 'ls',
      selection: TextSelection.collapsed(offset: 1),
    );
    expect(insertTranscript(value, ''), value);
  });

  test('appends when the selection points past the end of the text', () {
    // A stale selection left over from a longer draft must not throw.
    const value = TextEditingValue(
      text: 'ls',
      selection: TextSelection.collapsed(offset: 99),
    );
    final result = insertTranscript(value, ' -la');
    expect(result.text, 'ls -la');
    expect(result.selection, const TextSelection.collapsed(offset: 6));
  });

  test('accumulates across successive inserts', () {
    // Each final result from the recognizer is a separate insert; they have to
    // read as one dictated line.
    var value = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
    );
    for (final chunk in ['git ', 'commit ', '-m hello']) {
      value = insertTranscript(value, chunk);
    }
    expect(value.text, 'git commit -m hello');
    expect(value.selection, const TextSelection.collapsed(offset: 19));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd client && flutter test test/services/stt/transcript_insertion_test.dart
```

预期：编译失败，`Error: Couldn't resolve the package 'teampilot' ... transcript_insertion.dart` 或 `Target of URI doesn't exist`。

- [ ] **Step 3: 写 `transcript_insertion.dart`**

```dart
import 'package:flutter/services.dart';

/// Inserts recognized speech into a field's value at the caret.
///
/// Replaces the current selection, then collapses the caret after the inserted
/// text so successive final results read as one dictated line.
///
/// A field that has never been focused reports
/// `TextSelection.collapsed(offset: -1)`, and a stale selection can outlive the
/// text it indexed. Both make a naive
/// `text.replaceRange(selection.start, selection.end, text)` throw RangeError —
/// the reference implementation this was ported from does exactly that. Any
/// selection that does not index the current text appends instead.
TextEditingValue insertTranscript(TextEditingValue value, String text) {
  if (text.isEmpty) return value;
  final existing = value.text;
  final selection = value.selection;
  final indexable =
      selection.isValid &&
      selection.start >= 0 &&
      selection.end <= existing.length;
  if (!indexable) {
    final appended = existing + text;
    return TextEditingValue(
      text: appended,
      selection: TextSelection.collapsed(offset: appended.length),
    );
  }
  final updated = existing.replaceRange(selection.start, selection.end, text);
  return TextEditingValue(
    text: updated,
    selection: TextSelection.collapsed(offset: selection.start + text.length),
  );
}
```

- [ ] **Step 4: 写 `stt_provider.dart`**

```dart
/// Which recognition backend is in use.
enum SttProviderType { system, volcengine, aliyun }

/// One recognition result. [isFinal] separates a settled sentence from an
/// interim guess; only final results are inserted into the composer.
class SttResult {
  const SttResult({required this.text, required this.isFinal});

  final String text;
  final bool isFinal;
}

/// The OS refused microphone access.
///
/// Distinct from [SttException] because it is the one failure the user can fix,
/// and the fix is outside the app.
class VoicePermissionDeniedException implements Exception {
  const VoicePermissionDeniedException();

  @override
  String toString() => 'VoicePermissionDeniedException';
}

/// Any other recognition failure: handshake, auth, transport, recognizer.
class SttException implements Exception {
  const SttException(this.message);

  final String message;

  @override
  String toString() => 'SttException: $message';
}

/// The slice of a WebSocket the cloud providers use.
///
/// Deliberately narrower than `WebSocketChannel`: a test's stand-in for that
/// class has to stub a dozen `StreamChannel` members it never uses, so the seam
/// is defined here instead and the real socket adapts to it
/// ([WebSocketSttSocket] in `stt_socket.dart`).
abstract class SttSocket {
  /// Incoming frames — `String` for the JSON protocols, `List<int>` for binary.
  Stream<dynamic> get messages;

  void send(Object data);

  Future<void> close();
}

/// Injection seam for the two cloud providers' sockets, so their tests run
/// against a fake socket instead of the network.
typedef SttSocketFactory =
    Future<SttSocket> Function(Uri url, {Map<String, String>? headers});

/// One speech-recognition backend.
///
/// [start] emits until [stop] is called, the backend closes the session, or it
/// fails — a failure arrives as a stream error carrying
/// [VoicePermissionDeniedException] or [SttException].
abstract class SttProvider {
  /// Whether this backend can run at all: the recognizer initializes, or the
  /// credentials it needs are present.
  Future<bool> isAvailable();

  Stream<SttResult> start({String? localeId});

  /// Completes `true` once the session is live and speech will be recognized,
  /// `false` if setup failed.
  ///
  /// Only valid after [start]. The UI needs this because a cloud session can
  /// take a second or two to mint a token and finish a handshake, and a mic
  /// button that looks idle through that window reads as an unresponsive tap.
  /// It resolves `false` rather than throwing so the stream stays the single
  /// error channel — a rejected future nobody awaited would surface as an
  /// unhandled async error instead of as a message to the user.
  Future<bool> get ready;

  Future<void> stop();

  /// Round-trip milliseconds to a working session. Throws on failure — the
  /// settings page uses it to tell the user whether their credentials work.
  Future<int> testConnection();

  void dispose();
}
```

- [ ] **Step 5: 跑测试确认通过**

```bash
cd client && flutter test test/services/stt/transcript_insertion_test.dart
```

预期：`All tests passed!`，7 个测试。

- [ ] **Step 6: analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/stt test/services/stt
```

预期：`No issues found!`

- [ ] **Step 7: 提交**

```bash
cd /Users/yitouxiaomaolv/git/cmux && git add \
  client/lib/services/stt/stt_provider.dart \
  client/lib/services/stt/transcript_insertion.dart \
  client/test/services/stt/transcript_insertion_test.dart && \
git commit -m "feat(voice): add STT provider interface and transcript insertion

insertTranscript guards the two selection states that make a naive
replaceRange throw: an unfocused field's offset -1, and a selection left
over from longer text."
```

---

### Task 2: 豆包二进制封帧

**Files:**
- Create: `client/lib/services/stt/volcengine_frame_codec.dart`
- Test: `client/test/services/stt/volcengine_frame_codec_test.dart`
- Reference（只读，勿改）: `/Users/yitouxiaomaolv/git/Nexterm/nexterm/lib/features/terminal/services/stt/volcengine_stt_provider.dart` — `_buildFrame` 在 :227，`_handleServerMessage` 在 :127

**Interfaces:**
- Consumes: 无（本任务与 Task 1 无耦合，可并行）。
- Produces:
  - `class VolcMessageType { static const int fullClientRequest = 0x01; static const int audioOnlyRequest = 0x02; static const int fullServerResponse = 0x09; static const int errorResponse = 0x0f; }`
  - `class VolcSerialization { static const int raw = 0x00; static const int json = 0x01; }`
  - `class VolcFrame { const VolcFrame({required int messageType, required int flags, required int sequence, required List<int> payload}); }`
  - `Uint8List buildVolcFrame({required int messageType, required int serialization, required int flags, required int sequence, required List<int> payload})`
  - `VolcFrame parseVolcFrame(List<int> bytes)`

**协议（来自 spec，实现时以上面那份 Nexterm 文件为字节级准绳）：** 4 字节头 —— `byte0 = 0x11`（协议版本 1、header size 1 即 4 字节）、`byte1 = messageType << 4 | flags`、`byte2 = serialization << 4 | compression`、`byte3 = 0`；随后 int32 big-endian 序号 + uint32 big-endian payload 长度 + payload。压缩恒为 gzip（`compression = 0x01`）。配置帧 `messageType 0x01` + `serialization` JSON；音频帧 `messageType 0x02` + `serialization` raw。末包序号取负、`flags = 0x03`。服务端 `0x09` 为结果、`0x0f` 为错误。

- [ ] **Step 1: 读参照实现的解帧部分**

打开 `/Users/yitouxiaomaolv/git/Nexterm/nexterm/lib/features/terminal/services/stt/volcengine_stt_provider.dart`，完整读 `_buildFrame`（:227 起）与 `_handleServerMessage`（:127 起）。**服务端帧的字段偏移必须照它逐字节移植** —— 错误帧与结果帧的头后字段布局不同（错误帧的 4 字节位置放的是错误码而非序号），这一点不要凭协议描述猜。把你读到的实际布局写进 `parseVolcFrame` 的文档注释里。

- [ ] **Step 2: 写失败的测试**

`client/test/services/stt/volcengine_frame_codec_test.dart`：

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/stt/volcengine_frame_codec.dart';

void main() {
  group('buildVolcFrame', () {
    test('lays out the 4-byte header then int32 seq and uint32 length', () {
      final frame = buildVolcFrame(
        messageType: VolcMessageType.fullClientRequest,
        serialization: VolcSerialization.json,
        flags: 0x01,
        sequence: 1,
        payload: utf8.encode('{}'),
      );
      expect(frame[0], 0x11, reason: 'protocol version 1, header size 1');
      expect(frame[1], (0x01 << 4) | 0x01);
      expect(frame[2], (VolcSerialization.json << 4) | 0x01, reason: 'gzip');
      expect(frame[3], 0x00);

      final header = ByteData.sublistView(frame, 0, 12);
      expect(header.getInt32(4), 1, reason: 'big-endian by default');
      final gzipped = gzip.encode(utf8.encode('{}'));
      expect(header.getUint32(8), gzipped.length);
      expect(frame.sublist(12), gzipped);
    });

    test('gzips the payload', () {
      // A raw-serialization audio frame carries PCM, not JSON, but is still
      // compressed — the server rejects an uncompressed body.
      final pcm = Uint8List(3200); // 100 ms of 16 kHz 16-bit silence
      final frame = buildVolcFrame(
        messageType: VolcMessageType.audioOnlyRequest,
        serialization: VolcSerialization.raw,
        flags: 0x00,
        sequence: 2,
        payload: pcm,
      );
      expect(frame[2], (VolcSerialization.raw << 4) | 0x01);
      final body = frame.sublist(12);
      expect(body.length, lessThan(pcm.length), reason: 'silence compresses');
      expect(gzip.decode(body), pcm);
    });

    test('encodes a negative sequence for the last packet', () {
      // The final audio frame flags the end of the utterance with a negated
      // sequence; an unsigned write here would send a huge positive number and
      // the server would keep waiting for more audio.
      final frame = buildVolcFrame(
        messageType: VolcMessageType.audioOnlyRequest,
        serialization: VolcSerialization.raw,
        flags: 0x03,
        sequence: -7,
        payload: const <int>[],
      );
      expect(frame[1] & 0x0f, 0x03);
      expect(ByteData.sublistView(frame, 0, 12).getInt32(4), -7);
    });
  });

  group('parseVolcFrame', () {
    test('round-trips a frame built by buildVolcFrame', () {
      final payload = utf8.encode('{"result":{"text":"ls"}}');
      final wire = buildVolcFrame(
        messageType: VolcMessageType.fullServerResponse,
        serialization: VolcSerialization.json,
        flags: 0x00,
        sequence: 5,
        payload: payload,
      );
      final parsed = parseVolcFrame(wire);
      expect(parsed.messageType, VolcMessageType.fullServerResponse);
      expect(parsed.sequence, 5);
      expect(parsed.payload, payload, reason: 'gunzipped by the parser');
    });

    test('reports the message type of an error frame', () {
      final wire = buildVolcFrame(
        messageType: VolcMessageType.errorResponse,
        serialization: VolcSerialization.json,
        flags: 0x00,
        sequence: 0,
        payload: utf8.encode('{"error":"bad token"}'),
      );
      expect(parseVolcFrame(wire).messageType, VolcMessageType.errorResponse);
    });

    test('throws FormatException on a truncated frame', () {
      expect(
        () => parseVolcFrame(const <int>[0x11, 0x10]),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when the length field overruns the buffer', () {
      final wire = Uint8List(12);
      wire[0] = 0x11;
      ByteData.sublistView(wire).setUint32(8, 999);
      expect(() => parseVolcFrame(wire), throwsA(isA<FormatException>()));
    });
  });
}
```

- [ ] **Step 3: 跑测试确认失败**

```bash
cd client && flutter test test/services/stt/volcengine_frame_codec_test.dart
```

预期：`Target of URI doesn't exist: 'package:teampilot/services/stt/volcengine_frame_codec.dart'`。

- [ ] **Step 4: 写 `volcengine_frame_codec.dart`**

要求：
- 纯函数，只 import `dart:io`（gzip）、`dart:typed_data`。**不 import 任何 socket / http / flutter**。
- `buildVolcFrame` 用 `ByteData` 写头，`setInt32(4, sequence)` 与 `setUint32(8, length)` 都走默认 big-endian。
- `parseVolcFrame` 先校验 `bytes.length >= 12`，再校验 `12 + length <= bytes.length`，两处都抛 `FormatException` 并在消息里带上实际长度。`compression == 0x01` 时 `gzip.decode`，否则原样返回。
- 类文档注释里写清 Step 1 读到的服务端帧真实布局。

- [ ] **Step 5: 跑测试确认通过**

```bash
cd client && flutter test test/services/stt/volcengine_frame_codec_test.dart
```

预期：`All tests passed!`，7 个测试。

- [ ] **Step 6: analyze 并提交**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/stt test/services/stt
cd /Users/yitouxiaomaolv/git/cmux && git add \
  client/lib/services/stt/volcengine_frame_codec.dart \
  client/test/services/stt/volcengine_frame_codec_test.dart && \
git commit -m "feat(voice): add Volcengine binary frame codec

Pure build/parse with no socket dependency, so the wire format is
golden-tested. The last audio packet's sequence is negated, which needs a
signed int32 write."
```

---

### Task 3: 阿里签名与 token 服务

**Files:**
- Create: `client/lib/services/stt/aliyun_signature.dart`
- Create: `client/lib/services/stt/aliyun_token_service.dart`
- Test: `client/test/services/stt/aliyun_signature_test.dart`
- Test: `client/test/services/stt/aliyun_token_service_test.dart`
- Reference（只读）: `/Users/yitouxiaomaolv/git/Nexterm/nexterm/lib/features/terminal/services/stt/aliyun_token_service.dart`

**Interfaces:**
- Consumes: `SttException`（Task 1，`package:teampilot/services/stt/stt_provider.dart`）。
- Produces:
  - `String aliyunPercentEncode(String input)`
  - `String aliyunStringToSign(Map<String, String> params)`
  - `String aliyunSignature(Map<String, String> params, String accessKeySecret)`
  - `class AliyunTokenService` — 构造 `AliyunTokenService({required http.Client client, required String Function() nonceFactory, required DateTime Function() now})`，方法 `Future<String> getToken({required String accessKeyId, required String accessKeySecret})`

**算法（阿里云 RPC 风格，HMAC-SHA1）：**
1. 参数按 key 的字典序排序（不含 `Signature` 本身）。
2. 规范化查询串：`aliyunPercentEncode(k) + '=' + aliyunPercentEncode(v)`，以 `&` 连接。
3. `stringToSign = 'GET&' + aliyunPercentEncode('/') + '&' + aliyunPercentEncode(canonicalizedQuery)`，其中 `aliyunPercentEncode('/')` 即 `%2F`。
4. `signature = base64(HMAC_SHA1(key: accessKeySecret + '&', data: stringToSign))`。
5. percent-encode 的未保留字符集恰为 `A-Za-z0-9-_.~`，其余按 UTF-8 逐字节转大写十六进制。**不要用 `Uri.encodeComponent` / `Uri.encodeQueryComponent`** —— 它们放过 `!*'()`，阿里要求这些必须编码，且 `encodeQueryComponent` 把空格编成 `+`。

- [ ] **Step 1: 写 `aliyun_signature_test.dart`**

```dart
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/stt/aliyun_signature.dart';

void main() {
  group('aliyunPercentEncode', () {
    test('leaves only the unreserved set alone', () {
      expect(aliyunPercentEncode('aZ09-_.~'), 'aZ09-_.~');
    });

    test('encodes the characters Uri.encodeComponent lets through', () {
      // Dart's own encoders pass !*'() straight through; Alibaba's canonical
      // form requires them escaped, so a stock encoder silently signs the wrong
      // string and every request comes back SignatureDoesNotMatch.
      expect(aliyunPercentEncode("!*'()"), '%21%2A%27%28%29');
    });

    test('encodes space as %20, never +', () {
      expect(aliyunPercentEncode('a b'), 'a%20b');
    });

    test('encodes / and & and =', () {
      expect(aliyunPercentEncode('/'), '%2F');
      expect(aliyunPercentEncode('a&b=c'), 'a%26b%3Dc');
    });

    test('encodes multi-byte UTF-8 per byte in uppercase hex', () {
      expect(aliyunPercentEncode('中'), '%E4%B8%AD');
    });
  });

  group('aliyunStringToSign', () {
    test('sorts params, joins with &, then encodes the whole query once', () {
      final stringToSign = aliyunStringToSign({
        'Version': '2019-02-28',
        'Action': 'CreateToken',
        'Format': 'JSON',
      });
      // Sorted: Action, Format, Version. The inner = and & are encoded by the
      // outer pass, which is what makes this a single deterministic string.
      expect(
        stringToSign,
        'GET&%2F&Action%3DCreateToken%26Format%3DJSON%26Version%3D2019-02-28',
      );
    });

    test('excludes any Signature already present', () {
      final stringToSign = aliyunStringToSign({
        'Action': 'CreateToken',
        'Signature': 'stale',
      });
      expect(stringToSign, 'GET&%2F&Action%3DCreateToken');
    });
  });

  group('aliyunSignature', () {
    test('is HMAC-SHA1 over the stringToSign, keyed by secret + &', () {
      const params = {'Action': 'CreateToken', 'Format': 'JSON'};
      const secret = 'testsecret';
      // Recomputing the one-line formula here is deliberate. What this pins is
      // the wiring, which is where this signing scheme actually goes wrong:
      // that the HMAC covers the stringToSign (not the raw query), that the key
      // is secret + '&' (not the bare secret), that it is SHA-1 (not SHA-256),
      // and that the digest is base64 (not hex).
      final expected = base64Encode(
        Hmac(sha1, utf8.encode('$secret&'))
            .convert(utf8.encode(aliyunStringToSign(params)))
            .bytes,
      );
      expect(aliyunSignature(params, secret), expected);
    });

    test('changes when the secret changes', () {
      const params = {'Action': 'CreateToken'};
      expect(
        aliyunSignature(params, 'one'),
        isNot(aliyunSignature(params, 'two')),
      );
    });

    test('is independent of the input map order', () {
      const secret = 'testsecret';
      expect(
        aliyunSignature({'B': '2', 'A': '1'}, secret),
        aliyunSignature({'A': '1', 'B': '2'}, secret),
      );
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd client && flutter test test/services/stt/aliyun_signature_test.dart
```

预期：`Target of URI doesn't exist: 'package:teampilot/services/stt/aliyun_signature.dart'`。

- [ ] **Step 3: 写 `aliyun_signature.dart`**

```dart
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Exactly the unreserved set Alibaba's RPC signing requires. Dart's own
/// `Uri.encodeComponent` / `encodeQueryComponent` pass `!*'()` through and turn
/// a space into `+`, either of which signs a different string than the server
/// reconstructs — the failure surfaces as SignatureDoesNotMatch with nothing to
/// point at.
const _unreserved =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~';

/// Percent-encodes [input] per Alibaba's RPC rules: UTF-8 bytes, uppercase hex.
String aliyunPercentEncode(String input) {
  final out = StringBuffer();
  for (final byte in utf8.encode(input)) {
    final char = String.fromCharCode(byte);
    if (_unreserved.contains(char)) {
      out.write(char);
    } else {
      out.write('%');
      out.write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
  }
  return out.toString();
}

/// Builds the canonical string an Alibaba RPC GET signature covers.
///
/// Any `Signature` already in [params] is dropped: signing over a previous
/// signature is never correct and would make a retry unverifiable.
String aliyunStringToSign(Map<String, String> params) {
  final keys = params.keys.where((k) => k != 'Signature').toList()..sort();
  final canonical = keys
      .map((k) => '${aliyunPercentEncode(k)}=${aliyunPercentEncode(params[k]!)}')
      .join('&');
  return 'GET&${aliyunPercentEncode('/')}&${aliyunPercentEncode(canonical)}';
}

/// HMAC-SHA1 over [aliyunStringToSign], keyed by the secret with a trailing `&`
/// (the RPC scheme's empty second key component), base64 encoded.
String aliyunSignature(Map<String, String> params, String accessKeySecret) {
  final mac = Hmac(sha1, utf8.encode('$accessKeySecret&'));
  return base64Encode(
    mac.convert(utf8.encode(aliyunStringToSign(params))).bytes,
  );
}
```

- [ ] **Step 4: 跑测试确认通过**

```bash
cd client && flutter test test/services/stt/aliyun_signature_test.dart
```

预期：`All tests passed!`，10 个测试。

- [ ] **Step 5: 写 `aliyun_token_service_test.dart`**

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/services/stt/aliyun_token_service.dart';
import 'package:teampilot/services/stt/stt_provider.dart';

void main() {
  /// Unix seconds, as the CreateToken response reports expiry.
  int secondsSinceEpoch(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;

  late DateTime now;
  late List<Uri> requested;

  setUp(() {
    now = DateTime.utc(2026, 8, 2, 12);
    requested = [];
  });

  /// A CreateToken endpoint that always succeeds, expiring [ttl] from [now].
  MockClient okClient({Duration ttl = const Duration(hours: 1)}) {
    return MockClient((request) async {
      requested.add(request.url);
      return http.Response(
        jsonEncode({
          'Token': {
            'Id': 'token-${requested.length}',
            'ExpireTime': secondsSinceEpoch(now.add(ttl)),
          },
        }),
        200,
      );
    });
  }

  AliyunTokenService serviceWith(http.Client client) => AliyunTokenService(
    client: client,
    nonceFactory: () => 'fixed-nonce',
    now: () => now,
  );

  test('returns the token id from the response', () async {
    final service = serviceWith(okClient());
    final token = await service.getToken(
      accessKeyId: 'id',
      accessKeySecret: 'secret',
    );
    expect(token, 'token-1');
  });

  test('signs the request with the documented parameter set', () async {
    final service = serviceWith(okClient());
    await service.getToken(accessKeyId: 'id', accessKeySecret: 'secret');
    final query = requested.single.queryParameters;
    expect(requested.single.host, 'nls-meta.cn-shanghai.aliyuncs.com');
    expect(query['Action'], 'CreateToken');
    expect(query['Version'], '2019-02-28');
    expect(query['AccessKeyId'], 'id');
    expect(query['SignatureMethod'], 'HMAC-SHA1');
    expect(query['SignatureVersion'], '1.0');
    expect(query['SignatureNonce'], 'fixed-nonce');
    // Second-precision UTC, no fractional part — the gateway rejects anything
    // else with an InvalidTimeStamp error.
    expect(query['Timestamp'], '2026-08-02T12:00:00Z');
    expect(query['Signature'], isNotEmpty);
  });

  test('reuses a cached token instead of signing again', () async {
    final service = serviceWith(okClient());
    await service.getToken(accessKeyId: 'id', accessKeySecret: 'secret');
    final second = await service.getToken(
      accessKeyId: 'id',
      accessKeySecret: 'secret',
    );
    expect(second, 'token-1');
    expect(requested, hasLength(1));
  });

  test('refetches once the cached token is near expiry', () async {
    final service = serviceWith(okClient(ttl: const Duration(minutes: 10)));
    await service.getToken(accessKeyId: 'id', accessKeySecret: 'secret');
    now = now.add(const Duration(minutes: 10));
    final second = await service.getToken(
      accessKeyId: 'id',
      accessKeySecret: 'secret',
    );
    expect(second, 'token-2');
    expect(requested, hasLength(2));
  });

  test('refetches when the credentials change', () async {
    // A cached token belongs to the key that minted it; handing it to a new key
    // pair would fail the WebSocket handshake with a stale-token error that
    // looks like a code bug.
    final service = serviceWith(okClient());
    await service.getToken(accessKeyId: 'id', accessKeySecret: 'secret');
    final second = await service.getToken(
      accessKeyId: 'other',
      accessKeySecret: 'secret',
    );
    expect(second, 'token-2');
    expect(requested, hasLength(2));
  });

  test('throws SttException on a non-200 response', () async {
    final service = serviceWith(
      MockClient((_) async => http.Response('{"Message":"denied"}', 403)),
    );
    await expectLater(
      service.getToken(accessKeyId: 'id', accessKeySecret: 'bad'),
      throwsA(isA<SttException>()),
    );
  });

  test('throws SttException when the body carries no token', () async {
    final service = serviceWith(
      MockClient((_) async => http.Response('{"Token":{}}', 200)),
    );
    await expectLater(
      service.getToken(accessKeyId: 'id', accessKeySecret: 'secret'),
      throwsA(isA<SttException>()),
    );
  });

  test('throws SttException on a malformed body', () async {
    final service = serviceWith(
      MockClient((_) async => http.Response('not json', 200)),
    );
    await expectLater(
      service.getToken(accessKeyId: 'id', accessKeySecret: 'secret'),
      throwsA(isA<SttException>()),
    );
  });
}
```

- [ ] **Step 6: 跑测试确认失败**

```bash
cd client && flutter test test/services/stt/aliyun_token_service_test.dart
```

预期：`Target of URI doesn't exist: 'package:teampilot/services/stt/aliyun_token_service.dart'`。

- [ ] **Step 7: 写 `aliyun_token_service.dart`**

要求：

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'aliyun_signature.dart';
import 'stt_provider.dart';

/// Mints and caches the short-lived token the NLS WebSocket gateway wants.
///
/// The AccessKey pair never goes near the socket: it signs one RPC here, and
/// only the resulting token travels in the WebSocket URL.
class AliyunTokenService {
  AliyunTokenService({
    required http.Client client,
    required String Function() nonceFactory,
    required DateTime Function() now,
  }) : _client = client,
       _nonceFactory = nonceFactory,
       _now = now;

  static const _endpoint = 'https://nls-meta.cn-shanghai.aliyuncs.com/';

  /// Renew this early so a token cannot expire mid-handshake.
  static const _renewMargin = Duration(minutes: 1);

  final http.Client _client;
  final String Function() _nonceFactory;
  final DateTime Function() _now;

  String? _token;
  DateTime? _expiresAt;
  String? _cachedForKeyId;

  Future<String> getToken({
    required String accessKeyId,
    required String accessKeySecret,
  }) async {
    // ... 缓存命中条件：_token != null && _cachedForKeyId == accessKeyId
    //     && _expiresAt != null && _now().add(_renewMargin).isBefore(_expiresAt!)
  }
}
```

实现细节，逐条照做：

- 参数表：`AccessKeyId`、`Action: 'CreateToken'`、`Format: 'JSON'`、`RegionId: 'cn-shanghai'`、`SignatureMethod: 'HMAC-SHA1'`、`SignatureNonce: _nonceFactory()`、`SignatureVersion: '1.0'`、`Timestamp`、`Version: '2019-02-28'`。
- `Timestamp` 取 `_now().toUtc()` 格式化为 `yyyy-MM-ddTHH:mm:ssZ`，**秒精度、无小数**。用手写拼接（`toIso8601String()` 会带毫秒）：
  ```dart
  String _timestamp(DateTime at) {
    final u = at.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)}'
        'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
  }
  ```
- 先算 `aliyunSignature(params, accessKeySecret)`，再把 `Signature` 塞进查询参数，用 `Uri.parse(_endpoint).replace(queryParameters: {...params, 'Signature': signature})` 发 GET。
- 非 200 抛 `SttException('Alibaba CreateToken failed: ${response.statusCode}')`。
- 解析 `jsonDecode(response.body)['Token']`；`Id` 为空或缺失抛 `SttException`；`jsonDecode` 的 `FormatException` 用 `on FormatException` 捕获后抛 `SttException`。
- `ExpireTime` 是 Unix 秒：`DateTime.fromMillisecondsSinceEpoch(expire * 1000, isUtc: true)`。
- 成功后写入 `_token` / `_expiresAt` / `_cachedForKeyId`。

- [ ] **Step 8: 跑测试确认通过**

```bash
cd client && flutter test test/services/stt/aliyun_token_service_test.dart
```

预期：`All tests passed!`，8 个测试。

- [ ] **Step 9: analyze 并提交**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/stt test/services/stt
cd /Users/yitouxiaomaolv/git/cmux && git add \
  client/lib/services/stt/aliyun_signature.dart \
  client/lib/services/stt/aliyun_token_service.dart \
  client/test/services/stt/aliyun_signature_test.dart \
  client/test/services/stt/aliyun_token_service_test.dart && \
git commit -m "feat(voice): add Alibaba RPC signing and token service

The percent encoder is hand-rolled because Dart's own encoders pass !*'()
through and turn a space into +, both of which sign a different string
than the gateway reconstructs. Tokens cache by ExpireTime and by the key
id that minted them."
```

---

### Task 4: 依赖、平台权限、音频采集与系统识别 provider

**Files:**
- Modify: `client/pubspec.yaml`
- Modify: `client/ios/Runner/Info.plist`
- Modify: `client/android/app/src/main/AndroidManifest.xml`
- Create: `client/lib/services/stt/pcm_audio_source.dart`
- Create: `client/lib/services/stt/speech_recognizer.dart`
- Create: `client/lib/services/stt/system_stt_provider.dart`
- Test: `client/test/services/stt/system_stt_provider_test.dart`
- Reference（只读）: `/Users/yitouxiaomaolv/git/Nexterm/nexterm/lib/features/terminal/services/stt/system_stt_provider.dart`、`audio_recorder_service.dart`

**Interfaces:**
- Consumes: `SttProvider`、`SttResult`、`SttException`、`VoicePermissionDeniedException`（Task 1）。
- Produces:
  - `class SpeechLocale { const SpeechLocale({required String id, required String name}); final String id; final String name; }`
  - `abstract class SpeechRecognizer` — `Future<bool> initialize()`、`Future<bool> hasPermission()`、`Future<void> listen({required void Function(String text, bool isFinal) onResult, required void Function() onDone, String? localeId})`、`Future<void> stop()`、`Future<List<SpeechLocale>> locales()`
  - `class PluginSpeechRecognizer implements SpeechRecognizer`
  - `abstract class PcmAudioSource` — `Future<bool> hasPermission()`、`Future<Stream<Uint8List>> start()`、`Future<void> stop()`、`Future<void> dispose()`
  - `class RecordPcmAudioSource implements PcmAudioSource`
  - `class SystemSttProvider implements SttProvider` — 构造 `SystemSttProvider(SpeechRecognizer recognizer)`

**为什么要这两层包装：** `record` 的 `AudioRecorder` 与 `speech_to_text` 的 `SpeechToText` 都是具体类，直接用会让每个 provider 测试都需要真插件、真麦克风。抽成两个窄接口后，Task 5/6 的 provider 测试塞手写假实现即可，测试里连 `record` / `speech_to_text` 都不用 import。

- [ ] **Step 1: 加依赖**

`client/pubspec.yaml` 的 `dependencies:` 段内加（放在 `crypto: ^3.0.7` 之后，保持既有的宽松分组风格）：

```yaml
  speech_to_text: ^7.0.0
  record: 5.1.0
```

`record` 锁精确版本，与参照实现一致。已存在的 `dependency_overrides:` 段内追加一行：

```yaml
  record_platform_interface: 1.1.0
```

- [ ] **Step 2: 拉依赖并确认可解析**

```bash
cd client && flutter pub get
```

预期：`Got dependencies!`（或 `Changed N dependencies!`）。若报版本冲突，把完整冲突文本连同它指名的包一起报告，**不要**擅自放宽其他包的约束。

- [ ] **Step 3: 加 iOS 权限说明**

`client/ios/Runner/Info.plist`，在既有 `NSCameraUsageDescription` / `NSLocalNetworkUsageDescription` 旁加两条：

```xml
	<key>NSMicrophoneUsageDescription</key>
	<string>TeamPilot uses the microphone for voice input in the terminal composer.</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>TeamPilot uses speech recognition to turn your voice into terminal input.</string>
```

缺 `NSMicrophoneUsageDescription` 时 iOS 会在请求麦克风的瞬间直接杀进程，不是返回 false。

- [ ] **Step 4: 加 Android 权限与查询**

`client/android/app/src/main/AndroidManifest.xml`，在既有 `<uses-permission>` 之后加：

```xml
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <queries>
        <intent>
            <action android:name="android.speech.RecognitionService"/>
        </intent>
    </queries>
```

`<queries>` 是 Android 11+ 的包可见性要求，缺了 `speech_to_text` 找不到系统识别服务，表现为 `initialize()` 恒返回 false —— 看起来像设备不支持，实则清单缺一段。

- [ ] **Step 5: 写 `system_stt_provider_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/stt/speech_recognizer.dart';
import 'package:teampilot/services/stt/stt_provider.dart';
import 'package:teampilot/services/stt/system_stt_provider.dart';

/// Hand-written stand-in for the on-device recognizer: the test drives results
/// by calling [emit] / [finish], so no plugin and no microphone are involved.
class FakeSpeechRecognizer implements SpeechRecognizer {
  FakeSpeechRecognizer({this.initializes = true, this.permitted = true});

  final bool initializes;
  final bool permitted;

  int initializeCalls = 0;
  int stopCalls = 0;
  String? listenedLocaleId;
  bool listening = false;

  void Function(String text, bool isFinal)? _onResult;
  void Function()? _onDone;

  void emit(String text, {required bool isFinal}) =>
      _onResult?.call(text, isFinal);

  void finish() {
    listening = false;
    _onDone?.call();
  }

  @override
  Future<bool> initialize() async {
    initializeCalls++;
    return initializes;
  }

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    required void Function() onDone,
    String? localeId,
  }) async {
    listening = true;
    listenedLocaleId = localeId;
    _onResult = onResult;
    _onDone = onDone;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    listening = false;
  }

  @override
  Future<List<SpeechLocale>> locales() async => const [
    SpeechLocale(id: 'en_US', name: 'English (US)'),
  ];
}

void main() {
  test('isAvailable reflects whether the recognizer initializes', () async {
    expect(
      await SystemSttProvider(FakeSpeechRecognizer()).isAvailable(),
      isTrue,
    );
    expect(
      await SystemSttProvider(
        FakeSpeechRecognizer(initializes: false),
      ).isAvailable(),
      isFalse,
    );
  });

  test('emits interim results then the final one', () async {
    final recognizer = FakeSpeechRecognizer();
    final provider = SystemSttProvider(recognizer);
    final results = <SttResult>[];
    final stream = provider.start(localeId: 'zh_CN');
    final done = stream.listen(results.add).asFuture<void>();
    await Future<void>.delayed(Duration.zero);

    recognizer.emit('git', isFinal: false);
    recognizer.emit('git commit', isFinal: true);
    recognizer.finish();
    await done;

    expect(recognizer.listenedLocaleId, 'zh_CN');
    expect(results.map((r) => r.text), ['git', 'git commit']);
    expect(results.map((r) => r.isFinal), [false, true]);
  });

  test('closes the stream when the recognizer finishes on its own', () async {
    final recognizer = FakeSpeechRecognizer();
    final provider = SystemSttProvider(recognizer);
    final done = provider.start().listen((_) {}).asFuture<void>();
    await Future<void>.delayed(Duration.zero);
    recognizer.finish();
    await expectLater(done, completes);
  });

  test('stop closes the stream and stops the recognizer', () async {
    final recognizer = FakeSpeechRecognizer();
    final provider = SystemSttProvider(recognizer);
    final done = provider.start().listen((_) {}).asFuture<void>();
    await Future<void>.delayed(Duration.zero);
    await provider.stop();
    await expectLater(done, completes);
    expect(recognizer.stopCalls, 1);
    expect(recognizer.listening, isFalse);
  });

  test('errors with VoicePermissionDeniedException when the mic is refused',
      () async {
    // Initialization succeeding while permission is refused is the iOS shape of
    // a denied mic; it has to reach the user as the one failure they can fix,
    // not as a generic recognition error.
    final provider = SystemSttProvider(
      FakeSpeechRecognizer(permitted: false),
    );
    await expectLater(
      provider.start(),
      emitsError(isA<VoicePermissionDeniedException>()),
    );
  });

  test('errors with SttException when initialization fails', () async {
    final provider = SystemSttProvider(
      FakeSpeechRecognizer(initializes: false),
    );
    await expectLater(provider.start(), emitsError(isA<SttException>()));
  });

  test('ready resolves true once the recognizer is listening', () async {
    final recognizer = FakeSpeechRecognizer();
    final provider = SystemSttProvider(recognizer);
    provider.start().listen((_) {});
    expect(await provider.ready, isTrue);
    expect(recognizer.listening, isTrue);
    await provider.stop();
  });

  test('ready resolves false when setup fails', () async {
    // False rather than throwing: the stream already carries the error, and a
    // rejected future would double-report it as an unhandled async error.
    final provider = SystemSttProvider(
      FakeSpeechRecognizer(initializes: false),
    );
    provider.start().listen((_) {}, onError: (_) {});
    expect(await provider.ready, isFalse);
  });

  test('testConnection reports zero for on-device recognition', () async {
    // Nothing to connect to. The settings page hides the button for this
    // provider; the zero is here so the interface stays uniform.
    expect(await SystemSttProvider(FakeSpeechRecognizer()).testConnection(), 0);
  });
}
```

- [ ] **Step 6: 跑测试确认失败**

```bash
cd client && flutter test test/services/stt/system_stt_provider_test.dart
```

预期：`Target of URI doesn't exist: 'package:teampilot/services/stt/speech_recognizer.dart'`。

- [ ] **Step 7: 写 `speech_recognizer.dart`**

```dart
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// A recognition language, as the picker shows it.
class SpeechLocale {
  const SpeechLocale({required this.id, required this.name});

  final String id;
  final String name;
}

/// The slice of on-device speech recognition this app uses.
///
/// `SpeechToText` is a concrete plugin class, so depending on it directly would
/// put a real recognizer and a real microphone in every test. Providers depend
/// on this instead and their tests hand-write a stand-in.
abstract class SpeechRecognizer {
  Future<bool> initialize();
  Future<bool> hasPermission();
  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    required void Function() onDone,
    String? localeId,
  });
  Future<void> stop();
  Future<List<SpeechLocale>> locales();
}

class PluginSpeechRecognizer implements SpeechRecognizer {
  PluginSpeechRecognizer({SpeechToText? speech})
    : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  void Function()? _onDone;

  @override
  Future<bool> initialize() => _speech.initialize();

  @override
  Future<bool> hasPermission() async => _speech.hasPermission;

  @override
  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    required void Function() onDone,
    String? localeId,
  }) {
    _onDone = onDone;
    return _speech.listen(
      onResult: (SpeechRecognitionResult result) =>
          onResult(result.recognizedWords, result.finalResult),
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        localeId: localeId,
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<List<SpeechLocale>> locales() async {
    final locales = await _speech.locales();
    return locales
        .map((l) => SpeechLocale(id: l.localeId, name: l.name))
        .toList();
  }
}
```

`onDone` 的接线：`initialize()` 时给 `SpeechToText.initialize` 传 `onStatus`，状态为 `'done'` 或 `'notListening'` 时调 `_onDone?.call()`。按参照实现（`system_stt_provider.dart`）的写法接，它在 `done` 后延时 200ms 再收尾，照抄该延时并在注释里写明原因。

- [ ] **Step 8: 写 `pcm_audio_source.dart`**

```dart
import 'dart:typed_data';

import 'package:record/record.dart';

/// A stream of raw 16 kHz / 16-bit / mono PCM — the format both cloud
/// recognizers want.
///
/// Abstract for the same reason as [SpeechRecognizer]: `AudioRecorder` is a
/// concrete plugin class, and the cloud providers' tests must not open a
/// microphone.
abstract class PcmAudioSource {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> start();
  Future<void> stop();
  Future<void> dispose();
}

class RecordPcmAudioSource implements PcmAudioSource {
  RecordPcmAudioSource({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> start() => _recorder.startStream(
    const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      numChannels: 1,
      sampleRate: 16000,
    ),
  );

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> dispose() async => _recorder.dispose();
}
```

- [ ] **Step 9: 写 `system_stt_provider.dart`**

要求：
- 构造 `SystemSttProvider(this._recognizer)`。
- `isAvailable()` = `_recognizer.initialize()`。
- `start({localeId})`：建 `StreamController<SttResult>`；`initialize()` 为 false 则 `addError(const SttException('speech recognizer unavailable'))` 后 close；`hasPermission()` 为 false 则 `addError(const VoicePermissionDeniedException())` 后 close；否则 `listen(onResult: (text, isFinal) => add(SttResult(...)), onDone: close, localeId: localeId)`。**控制器不加 `sync: true`**，用默认异步派发。
- `ready`：字段 `Completer<bool> _ready`，每次 `start()` 新建一个；`listen()` 接上后 `complete(true)`，初始化失败或权限被拒时 `complete(false)`。每处 complete 前判 `if (!_ready.isCompleted)`。getter 返回 `_ready.future`。
- `stop()`：`_recognizer.stop()` 后关闭控制器；重复调用安全（`controller?.isClosed` 判一下）。
- `testConnection()` 返回 `0`。
- `dispose()`：关闭控制器。

- [ ] **Step 10: 跑测试确认通过**

```bash
cd client && flutter test test/services/stt/system_stt_provider_test.dart
```

预期：`All tests passed!`，9 个测试。

- [ ] **Step 11: 全量 analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

预期：`No issues found!`（或仅有既存的 `onReorder` deprecated info —— 那是 A 期遗留，不要动）。

- [ ] **Step 12: 提交**

```bash
cd /Users/yitouxiaomaolv/git/cmux && git add \
  client/pubspec.yaml client/pubspec.lock \
  client/ios/Runner/Info.plist \
  client/android/app/src/main/AndroidManifest.xml \
  client/lib/services/stt/pcm_audio_source.dart \
  client/lib/services/stt/speech_recognizer.dart \
  client/lib/services/stt/system_stt_provider.dart \
  client/test/services/stt/system_stt_provider_test.dart && \
git commit -m "feat(voice): add audio source, recognizer wrapper and system STT

Both plugin classes are concrete, so each gets a narrow interface in front
of it — the cloud providers' tests then need neither a microphone nor the
plugins themselves. Android needs a <queries> entry for the recognition
service or initialize() just returns false on API 30+."
```

**注意**：`git add` 里只列上面这些路径。`client/ios/Flutter/*.xcconfig`、`project.pbxproj`、`Podfile*` 等既有未提交改动一律不碰。

---

### Task 5: 豆包 provider

**Files:**
- Create: `client/lib/services/stt/stt_socket.dart`
- Create: `client/lib/services/stt/volcengine_stt_provider.dart`
- Test: `client/test/services/stt/volcengine_stt_provider_test.dart`
- Test helper: `client/test/services/stt/stt_test_doubles.dart`
- Reference（只读）: `/Users/yitouxiaomaolv/git/Nexterm/nexterm/lib/features/terminal/services/stt/volcengine_stt_provider.dart`

**Interfaces:**
- Consumes: `SttProvider`、`SttResult`、`SttSocket`、`SttSocketFactory`、`SttException`、`VoicePermissionDeniedException`（Task 1）；`buildVolcFrame`、`parseVolcFrame`、`VolcMessageType`、`VolcSerialization`（Task 2）；`PcmAudioSource`（Task 4）。
- Produces:
  - `class WebSocketSttSocket implements SttSocket` — 静态 `Future<SttSocket> connect(Uri url, {Map<String, String>? headers})`，签名与 `SttSocketFactory` 一致
  - `class VolcengineSttProvider implements SttProvider` — 构造 `VolcengineSttProvider({required PcmAudioSource audio, required SttSocketFactory socketFactory, required String appId, required String accessToken, required String Function() requestIdFactory})`
  - 测试替身 `FakeSttSocket`、`FakePcmAudioSource`（供 Task 6 复用）

**连接参数：** URL `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_nostream`；header `X-Api-App-Key`=appId、`X-Api-Access-Key`=accessToken、`X-Api-Resource-Id`=`volc.seedasr.sauc.duration`、`X-Api-Request-Id`=`requestIdFactory()`。配置 JSON：`{'audio': {'format': 'pcm', 'rate': 16000, 'bits': 16, 'channel': 1, 'language': localeId ?? 'zh-CN'}, 'request': {'model_name': 'bigmodel', 'enable_itn': true, 'enable_punc': true, 'result_type': 'full', 'show_utterances': true}}`。

- [ ] **Step 1: 写测试替身 `stt_test_doubles.dart`**

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:teampilot/services/stt/pcm_audio_source.dart';
import 'package:teampilot/services/stt/stt_provider.dart';

/// A socket the test drives by hand: [sent] records everything the provider
/// wrote, [deliver] pushes a frame back as if the server had sent it.
class FakeSttSocket implements SttSocket {
  final _incoming = StreamController<dynamic>();
  final sent = <Object>[];
  var closed = false;

  @override
  Stream<dynamic> get messages => _incoming.stream;

  @override
  void send(Object data) => sent.add(data);

  @override
  Future<void> close() async {
    closed = true;
    if (!_incoming.isClosed) await _incoming.close();
  }

  void deliver(Object frame) => _incoming.add(frame);

  void failWith(Object error) => _incoming.addError(error);

  /// Server hung up without saying anything.
  Future<void> endStream() async {
    if (!_incoming.isClosed) await _incoming.close();
  }
}

/// A microphone the test drives by hand.
class FakePcmAudioSource implements PcmAudioSource {
  FakePcmAudioSource({this.permitted = true});

  final bool permitted;
  final _chunks = StreamController<Uint8List>();
  var started = false;
  var stopped = false;
  var disposed = false;

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<Stream<Uint8List>> start() async {
    started = true;
    return _chunks.stream;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    if (!_chunks.isClosed) await _chunks.close();
  }

  @override
  Future<void> dispose() async => disposed = true;

  void emit(Uint8List pcm) => _chunks.add(pcm);
}
```

- [ ] **Step 2: 写 `volcengine_stt_provider_test.dart`**

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/stt/stt_provider.dart';
import 'package:teampilot/services/stt/volcengine_frame_codec.dart';
import 'package:teampilot/services/stt/volcengine_stt_provider.dart';

import 'stt_test_doubles.dart';

void main() {
  late FakeSttSocket socket;
  late FakePcmAudioSource audio;
  late Uri connectedTo;
  late Map<String, String>? sentHeaders;

  VolcengineSttProvider build({bool permitted = true}) {
    audio = FakePcmAudioSource(permitted: permitted);
    socket = FakeSttSocket();
    return VolcengineSttProvider(
      audio: audio,
      socketFactory: (url, {headers}) async {
        connectedTo = url;
        sentHeaders = headers;
        return socket;
      },
      appId: 'app-id',
      accessToken: 'access-token',
      requestIdFactory: () => 'request-id',
    );
  }

  /// The parsed frames the provider wrote, in order.
  List<VolcFrame> writtenFrames() =>
      socket.sent.map((f) => parseVolcFrame(f as List<int>)).toList();

  /// A server result frame carrying [text].
  Uint8List resultFrame({
    required String text,
    required bool definite,
    int sequence = 1,
  }) {
    return buildVolcFrame(
      messageType: VolcMessageType.fullServerResponse,
      serialization: VolcSerialization.json,
      flags: 0x00,
      sequence: sequence,
      payload: utf8.encode(
        jsonEncode({
          'result': {
            'text': text,
            'utterances': [
              {'text': text, 'definite': definite},
            ],
          },
        }),
      ),
    );
  }

  test('connects with the documented endpoint and headers', () async {
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);

    expect(connectedTo.scheme, 'wss');
    expect(connectedTo.host, 'openspeech.bytedance.com');
    expect(connectedTo.path, '/api/v3/sauc/bigmodel_nostream');
    expect(sentHeaders, {
      'X-Api-App-Key': 'app-id',
      'X-Api-Access-Key': 'access-token',
      'X-Api-Resource-Id': 'volc.seedasr.sauc.duration',
      'X-Api-Request-Id': 'request-id',
    });
    await provider.stop();
  });

  test('sends the config frame before any audio', () async {
    final provider = build();
    provider.start(localeId: 'en-US').listen((_) {});
    await Future<void>.delayed(Duration.zero);

    final first = writtenFrames().first;
    expect(first.messageType, VolcMessageType.fullClientRequest);
    final config = jsonDecode(utf8.decode(first.payload)) as Map;
    expect((config['audio'] as Map)['rate'], 16000);
    expect((config['audio'] as Map)['language'], 'en-US');
    expect((config['request'] as Map)['enable_punc'], isTrue);
    expect((config['request'] as Map)['enable_itn'], isTrue);
    await provider.stop();
  });

  test('defaults the language to zh-CN when no locale is chosen', () async {
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);

    final config =
        jsonDecode(utf8.decode(writtenFrames().first.payload)) as Map;
    expect((config['audio'] as Map)['language'], 'zh-CN');
    await provider.stop();
  });

  test('forwards audio chunks as raw-serialization frames, in order', () async {
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);

    audio.emit(Uint8List.fromList(List.filled(320, 1)));
    audio.emit(Uint8List.fromList(List.filled(320, 2)));
    await Future<void>.delayed(Duration.zero);

    final frames = writtenFrames();
    expect(frames, hasLength(3), reason: 'config + two audio frames');
    expect(frames[1].messageType, VolcMessageType.audioOnlyRequest);
    expect(frames[1].payload.first, 1);
    expect(frames[2].payload.first, 2);
    expect(
      frames[2].sequence,
      greaterThan(frames[1].sequence),
      reason: 'the server orders audio by sequence',
    );
    await provider.stop();
  });

  test('stop sends a negative-sequence last packet', () async {
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    audio.emit(Uint8List.fromList(List.filled(320, 1)));
    await Future<void>.delayed(Duration.zero);

    await provider.stop();

    final last = writtenFrames().last;
    expect(last.sequence, isNegative, reason: 'negation marks the end');
    expect(last.flags, 0x03);
    expect(audio.stopped, isTrue);
  });

  test('emits an interim result then a definite one', () async {
    final provider = build();
    final results = <SttResult>[];
    provider.start().listen(results.add);
    await Future<void>.delayed(Duration.zero);

    socket.deliver(resultFrame(text: 'git', definite: false));
    socket.deliver(resultFrame(text: 'git commit', definite: true));
    await Future<void>.delayed(Duration.zero);

    expect(results.map((r) => r.text), ['git', 'git commit']);
    expect(results.map((r) => r.isFinal), [false, true]);
    await provider.stop();
  });

  test('turns an error frame into an SttException on the stream', () async {
    final provider = build();
    final stream = provider.start();
    final errors = <Object>[];
    stream.listen((_) {}, onError: errors.add);
    await Future<void>.delayed(Duration.zero);

    socket.deliver(
      buildVolcFrame(
        messageType: VolcMessageType.errorResponse,
        serialization: VolcSerialization.json,
        flags: 0x00,
        sequence: 0,
        payload: utf8.encode('{"error":"invalid token"}'),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(errors.single, isA<SttException>());
  });

  test('errors with VoicePermissionDeniedException and never connects',
      () async {
    // Opening a paid cloud session the user cannot speak into wastes a
    // handshake and leaks the fact that they tried; refuse before connecting.
    final provider = build(permitted: false);
    await expectLater(
      provider.start(),
      emitsError(isA<VoicePermissionDeniedException>()),
    );
    expect(audio.started, isFalse);
  });

  test('ready resolves true once the config frame is out', () async {
    final provider = build();
    provider.start().listen((_) {});
    expect(await provider.ready, isTrue);
    expect(audio.started, isTrue);
    await provider.stop();
  });

  test('ready resolves false when the mic is refused', () async {
    final provider = build(permitted: false);
    provider.start().listen((_) {}, onError: (_) {});
    expect(await provider.ready, isFalse);
  });

  test('closes the socket and the microphone on stop', () async {
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    await provider.stop();
    expect(socket.closed, isTrue);
    expect(audio.stopped, isTrue);
  });

  test('stop is safe to call twice', () async {
    // The composer stops on close, on mode change and on dispose; two of those
    // can fire for one user action.
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    await provider.stop();
    await expectLater(provider.stop(), completes);
  });
}
```

- [ ] **Step 3: 跑测试确认失败**

```bash
cd client && flutter test test/services/stt/volcengine_stt_provider_test.dart
```

预期：`Target of URI doesn't exist: 'package:teampilot/services/stt/volcengine_stt_provider.dart'`。

- [ ] **Step 4: 写 `stt_socket.dart`**

```dart
import 'package:web_socket_channel/io.dart';

import 'stt_provider.dart';

/// [SttSocket] over a real WebSocket.
///
/// `IOWebSocketChannel` rather than `WebSocketChannel.connect` because
/// Volcengine authenticates with request headers, and only the IO channel can
/// set them.
class WebSocketSttSocket implements SttSocket {
  WebSocketSttSocket._(this._channel);

  final IOWebSocketChannel _channel;

  /// Matches [SttSocketFactory].
  static Future<SttSocket> connect(
    Uri url, {
    Map<String, String>? headers,
  }) async {
    final channel = IOWebSocketChannel.connect(url, headers: headers);
    await channel.ready;
    return WebSocketSttSocket._(channel);
  }

  @override
  Stream<dynamic> get messages => _channel.stream;

  @override
  void send(Object data) => _channel.sink.add(data);

  @override
  Future<void> close() => _channel.sink.close();
}
```

- [ ] **Step 5: 写 `volcengine_stt_provider.dart`**

要求，逐条照做：

- 构造参数如 Interfaces 所列，全部 `required`。
- 内部状态：`StreamController<SttResult>? _results`、`SttSocket? _socket`、`StreamSubscription? _socketSub`、`StreamSubscription<Uint8List>? _audioSub`、`int _sequence = 1`、`bool _stopping = false`。
- `isAvailable()` 返回 `appId.isNotEmpty && accessToken.isNotEmpty`。
- `start({localeId})`：
  1. 建 `_results = StreamController<SttResult>()`，**立即返回 `_results!.stream`**，异步部分放一个不 await 的私有 `_run(localeId)`，错误经 `_results!.addError` 送出。
  2. `_run` 里先 `await audio.hasPermission()`，false 则 `addError(const VoicePermissionDeniedException())` 并 close，**不连 socket、不开麦克风**。
  3. `await socketFactory(url, headers: …)`，订阅 `messages`：每条按 `parseVolcFrame` 解，`VolcMessageType.fullServerResponse` 走结果解析，`VolcMessageType.errorResponse` 走 `addError(SttException(...))` 并把 payload 文本带进消息。`onError` 转 `SttException`，`onDone` 关闭 `_results`。
  4. 发配置帧：`buildVolcFrame(messageType: fullClientRequest, serialization: json, flags: 0x01, sequence: _sequence, payload: utf8.encode(jsonEncode(config)))`。
  5. `await audio.start()` 拿到 PCM 流，订阅：每块 `_sequence++` 后发 `buildVolcFrame(messageType: audioOnlyRequest, serialization: raw, flags: 0x00, sequence: _sequence, payload: chunk)`。
- 结果解析：payload 解 JSON，取 `result` map；`text` 取 `result['text']` 转 `String`（缺失作 `''`）；`utterances` 取 `result['utterances']`，为非空 List 时 `isFinal = utterances.last['definite'] == true`，否则 `isFinal = false`。text 为空则不发。字段布局以参照实现 :187 为准。
- `stop()`：`_stopping` 已为真则直接 return；置真；发末包 `buildVolcFrame(messageType: audioOnlyRequest, serialization: raw, flags: 0x03, sequence: -_sequence, payload: const [])`；`await audio.stop()`；等待收尾 `await Future.delayed(const Duration(seconds: 3))` **但要能被 socket 提前关闭打断** —— 用 `Future.any([_socketDone.future, Future.delayed(...)])`，`_socketDone` 是 socket `onDone` 时 complete 的 `Completer<void>`；然后取消两个订阅、`await _socket?.close()`、关闭 `_results`。注释写明这 3 秒是等服务端把最后一句吐完，直接关会丢掉整句。
- `ready`：字段 `Completer<bool> _ready`，`start()` 时新建。配置帧发出且音频订阅建立后 `complete(true)`；权限被拒、连接抛异常、或收到错误帧而尚未就绪时 `complete(false)`。每处判 `isCompleted`。
- `dispose()`：`stop()` 的同步部分 + `audio.dispose()`。
- 文件不得超过 ~200 行；超了就把配置 JSON 构造抽成私有顶层函数。

- [ ] **Step 6: 跑测试确认通过**

```bash
cd client && flutter test test/services/stt/volcengine_stt_provider_test.dart
```

预期：`All tests passed!`，13 个测试。测试里 `stop()` 会走那 3 秒等待路径 —— 因为 `FakeSttSocket.close()` 会关掉 `messages`，`onDone` 立刻 complete `_socketDone`，`Future.any` 随即返回。若测试卡住 30 秒，说明 `_socketDone` 没接上，先修这个再往下。

- [ ] **Step 7: analyze 并提交**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd /Users/yitouxiaomaolv/git/cmux && git add \
  client/lib/services/stt/stt_socket.dart \
  client/lib/services/stt/volcengine_stt_provider.dart \
  client/test/services/stt/stt_test_doubles.dart \
  client/test/services/stt/volcengine_stt_provider_test.dart && \
git commit -m "feat(voice): add Volcengine STT provider

Refuses before connecting when the mic is denied, so a paid session is
never opened for audio that cannot arrive. stop() waits for the server's
trailing sentence but gives up as soon as the socket closes."
```

---

### Task 6: 阿里 NLS provider

**Files:**
- Create: `client/lib/services/stt/aliyun_stt_provider.dart`
- Test: `client/test/services/stt/aliyun_stt_provider_test.dart`
- Reference（只读）: `/Users/yitouxiaomaolv/git/Nexterm/nexterm/lib/features/terminal/services/stt/aliyun_stt_provider.dart`

**Interfaces:**
- Consumes: `SttProvider`、`SttResult`、`SttSocket`、`SttSocketFactory`、`SttException`、`VoicePermissionDeniedException`（Task 1）；`AliyunTokenService`（Task 3）；`PcmAudioSource`（Task 4）；`FakeSttSocket`、`FakePcmAudioSource`（Task 5 的 `stt_test_doubles.dart`）。
- Produces: `class AliyunSttProvider implements SttProvider` — 构造 `AliyunSttProvider({required PcmAudioSource audio, required SttSocketFactory socketFactory, required AliyunTokenService tokenService, required String accessKeyId, required String accessKeySecret, required String appKey, required String Function() idFactory})`

**协议：** URL `wss://nls-gateway-cn-shanghai.aliyuncs.com/ws/v1?token=$token`。消息为 JSON 文本，`header` 为 `{'appkey': appKey, 'message_id': idFactory(), 'task_id': <整个会话固定一个>, 'namespace': 'SpeechTranscriber', 'name': <事件名>}`。`message_id` 每条新生成，`task_id` 一个会话内固定。启动事件 `StartTranscription`，payload `{'format': 'pcm', 'sample_rate': 16000, 'enable_intermediate_result': true, 'enable_punctuation_prediction': true, 'enable_inverse_text_normalization': true, 'max_sentence_silence': 800}`。收到 `TranscriptionStarted` 后才可发裸二进制 PCM。结果：`TranscriptionResultChanged` → partial，`SentenceEnd` → final，文本在 `payload.result`。`TaskFailed` → 错误。停止发 `StopTranscription`，等 2 秒收尾。

- [ ] **Step 1: 写 `aliyun_stt_provider_test.dart`**

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/services/stt/aliyun_stt_provider.dart';
import 'package:teampilot/services/stt/aliyun_token_service.dart';
import 'package:teampilot/services/stt/stt_provider.dart';

import 'stt_test_doubles.dart';

void main() {
  late FakeSttSocket socket;
  late FakePcmAudioSource audio;
  late Uri connectedTo;
  late int idCalls;

  AliyunSttProvider build({bool permitted = true, int tokenStatus = 200}) {
    audio = FakePcmAudioSource(permitted: permitted);
    socket = FakeSttSocket();
    idCalls = 0;
    return AliyunSttProvider(
      audio: audio,
      socketFactory: (url, {headers}) async {
        connectedTo = url;
        return socket;
      },
      tokenService: AliyunTokenService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'Token': {'Id': 'the-token', 'ExpireTime': 4102444800},
            }),
            tokenStatus,
          ),
        ),
        nonceFactory: () => 'nonce',
        now: () => DateTime.utc(2026, 8, 2, 12),
      ),
      accessKeyId: 'id',
      accessKeySecret: 'secret',
      appKey: 'app-key',
      idFactory: () => 'id-${++idCalls}',
    );
  }

  /// The JSON messages the provider wrote, in order.
  List<Map<String, dynamic>> jsonSent() => socket.sent
      .whereType<String>()
      .map((s) => jsonDecode(s) as Map<String, dynamic>)
      .toList();

  /// The binary payloads the provider wrote.
  List<Object> binarySent() =>
      socket.sent.where((s) => s is! String).toList();

  /// A server event.
  String event(String name, {Map<String, dynamic>? payload}) => jsonEncode({
    'header': {'name': name, 'status': 20000000},
    if (payload != null) 'payload': payload,
  });

  test('puts the minted token in the gateway URL', () async {
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);

    expect(connectedTo.host, 'nls-gateway-cn-shanghai.aliyuncs.com');
    expect(connectedTo.path, '/ws/v1');
    expect(connectedTo.queryParameters['token'], 'the-token');
    await provider.stop();
  });

  test('sends StartTranscription with the documented payload', () async {
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);

    final start = jsonSent().single;
    expect(start['header']['name'], 'StartTranscription');
    expect(start['header']['namespace'], 'SpeechTranscriber');
    expect(start['header']['appkey'], 'app-key');
    expect(start['payload']['sample_rate'], 16000);
    expect(start['payload']['max_sentence_silence'], 800);
    expect(start['payload']['enable_punctuation_prediction'], isTrue);
    expect(start['payload']['enable_inverse_text_normalization'], isTrue);
    await provider.stop();
  });

  test('does not send PCM before TranscriptionStarted arrives', () async {
    // Audio sent ahead of the acknowledgement is discarded and the gateway
    // drops the task — the symptom is a session that connects fine and
    // recognizes nothing, with no error anywhere.
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);

    audio.emit(Uint8List.fromList(List.filled(320, 7)));
    await Future<void>.delayed(Duration.zero);
    expect(binarySent(), isEmpty);

    socket.deliver(event('TranscriptionStarted'));
    await Future<void>.delayed(Duration.zero);
    audio.emit(Uint8List.fromList(List.filled(320, 8)));
    await Future<void>.delayed(Duration.zero);
    expect(binarySent(), hasLength(1));
    await provider.stop();
  });

  test('reuses one task_id and a fresh message_id per message', () async {
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    socket.deliver(event('TranscriptionStarted'));
    await Future<void>.delayed(Duration.zero);
    await provider.stop();

    final messages = jsonSent();
    expect(messages, hasLength(2), reason: 'start then stop');
    final taskIds = messages.map((m) => m['header']['task_id']).toSet();
    expect(taskIds, hasLength(1), reason: 'one task per session');
    final messageIds = messages.map((m) => m['header']['message_id']).toSet();
    expect(messageIds, hasLength(2), reason: 'ids are per message');
  });

  test('maps TranscriptionResultChanged to a partial result', () async {
    final provider = build();
    final results = <SttResult>[];
    provider.start().listen(results.add);
    await Future<void>.delayed(Duration.zero);
    socket.deliver(event('TranscriptionStarted'));
    socket.deliver(
      event('TranscriptionResultChanged', payload: {'result': 'git'}),
    );
    await Future<void>.delayed(Duration.zero);

    expect(results.single.text, 'git');
    expect(results.single.isFinal, isFalse);
    await provider.stop();
  });

  test('maps SentenceEnd to a final result', () async {
    final provider = build();
    final results = <SttResult>[];
    provider.start().listen(results.add);
    await Future<void>.delayed(Duration.zero);
    socket.deliver(event('TranscriptionStarted'));
    socket.deliver(event('SentenceEnd', payload: {'result': 'git commit'}));
    await Future<void>.delayed(Duration.zero);

    expect(results.single.text, 'git commit');
    expect(results.single.isFinal, isTrue);
    await provider.stop();
  });

  test('turns TaskFailed into an SttException on the stream', () async {
    final provider = build();
    final errors = <Object>[];
    provider.start().listen((_) {}, onError: errors.add);
    await Future<void>.delayed(Duration.zero);
    socket.deliver(
      jsonEncode({
        'header': {'name': 'TaskFailed', 'status': 40000000},
        'payload': {'status_text': 'gateway rejected the task'},
      }),
    );
    await Future<void>.delayed(Duration.zero);

    expect(errors.single, isA<SttException>());
  });

  test('closes the stream on TranscriptionCompleted', () async {
    final provider = build();
    final done = provider.start().listen((_) {}).asFuture<void>();
    await Future<void>.delayed(Duration.zero);
    socket.deliver(event('TranscriptionStarted'));
    socket.deliver(event('TranscriptionCompleted'));
    await expectLater(done, completes);
  });

  test('errors with VoicePermissionDeniedException before minting a token',
      () async {
    // Minting a token is a signed API call. Doing it for a session the user
    // cannot speak into spends quota for nothing.
    final provider = build(permitted: false);
    await expectLater(
      provider.start(),
      emitsError(isA<VoicePermissionDeniedException>()),
    );
    expect(audio.started, isFalse);
  });

  test('errors with SttException when the token call fails', () async {
    final provider = build(tokenStatus: 403);
    await expectLater(provider.start(), emitsError(isA<SttException>()));
  });

  test('ready resolves true only after TranscriptionStarted', () async {
    // This is the visible half of the PCM gate: the mic button must not claim
    // to be listening while the gateway is still discarding audio.
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);

    var resolved = false;
    // ignore: unawaited_futures
    provider.ready.then((_) => resolved = true);
    await Future<void>.delayed(Duration.zero);
    expect(resolved, isFalse);

    socket.deliver(event('TranscriptionStarted'));
    expect(await provider.ready, isTrue);
    await provider.stop();
  });

  test('ready resolves false when the token call fails', () async {
    final provider = build(tokenStatus: 403);
    provider.start().listen((_) {}, onError: (_) {});
    expect(await provider.ready, isFalse);
  });

  test('stop sends StopTranscription and closes both ends', () async {
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    socket.deliver(event('TranscriptionStarted'));
    await Future<void>.delayed(Duration.zero);

    await provider.stop();

    expect(jsonSent().last['header']['name'], 'StopTranscription');
    expect(socket.closed, isTrue);
    expect(audio.stopped, isTrue);
  });

  test('stop is safe to call twice', () async {
    final provider = build();
    provider.start().listen((_) {});
    await Future<void>.delayed(Duration.zero);
    await provider.stop();
    await expectLater(provider.stop(), completes);
  });

  test('isAvailable requires all three credentials', () async {
    expect(await build().isAvailable(), isTrue);
    final missingAppKey = AliyunSttProvider(
      audio: FakePcmAudioSource(),
      socketFactory: (url, {headers}) async => FakeSttSocket(),
      tokenService: AliyunTokenService(
        client: MockClient((_) async => http.Response('{}', 200)),
        nonceFactory: () => 'nonce',
        now: DateTime.now,
      ),
      accessKeyId: 'id',
      accessKeySecret: 'secret',
      appKey: '',
      idFactory: () => 'id',
    );
    expect(await missingAppKey.isAvailable(), isFalse);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd client && flutter test test/services/stt/aliyun_stt_provider_test.dart
```

预期：`Target of URI doesn't exist: 'package:teampilot/services/stt/aliyun_stt_provider.dart'`。

- [ ] **Step 3: 写 `aliyun_stt_provider.dart`**

要求，逐条照做：

- `isAvailable()` 返回 `accessKeyId.isNotEmpty && accessKeySecret.isNotEmpty && appKey.isNotEmpty`。
- `start({localeId})` 与豆包同构：立刻返回 controller 的 stream，异步部分在私有 `_run` 里。
- `_run` 顺序：`audio.hasPermission()`（false 则 `VoicePermissionDeniedException` 并 close，**在取 token 之前**）→ `tokenService.getToken(...)`（`SttException` 直接透传到流上）→ `socketFactory` 连接 → 订阅消息 → 发 `StartTranscription` → `audio.start()` 订阅 PCM。
- **PCM 门闩**：私有 `bool _started = false`；音频订阅回调里 `if (!_started) return;`（丢弃而非缓冲 —— 缓冲会把握手期的旧音频在开始后一次灌进去，识别出一段错位的话）。`TranscriptionStarted` 到达时置 `_started = true`。这条要在注释里写清为什么是丢弃。
- `task_id` 在 `_run` 开头取一次 `idFactory()` 存字段；每条消息的 `message_id` 现取 `idFactory()`。
- 事件分发按 `header.name`：`TranscriptionStarted` → 开闩；`TranscriptionResultChanged` → `SttResult(text: payload['result'], isFinal: false)`；`SentenceEnd` → `isFinal: true`；`TranscriptionCompleted` → close；`TaskFailed` → `addError(SttException(payload?['status_text'] ?? 'task failed'))`。`payload['result']` 为空则不发。未知事件名忽略。
- 非 String 的入站消息忽略（网关只发文本）。
- `localeId` 在本 provider 无对应字段 —— 阿里的语言由 appKey 绑定的模型决定。**不要**编一个字段塞进 payload；在方法文档注释里写明该参数被有意忽略的原因。
- `ready`：字段 `Completer<bool> _ready`，`start()` 时新建。**只在 `TranscriptionStarted` 到达时 `complete(true)`** —— 这是 PCM 门闩的对外可见面，闩没开就不能对用户宣称在听。权限被拒、token 失败、连接异常、`TaskFailed` 且尚未就绪时 `complete(false)`。每处判 `isCompleted`。
- `stop()`：幂等（`_stopping` 守卫）；发 `StopTranscription`；`audio.stop()`；`Future.any([_socketDone.future, Future.delayed(const Duration(seconds: 2))])`；取消订阅、关 socket、关 controller。若 `_ready` 尚未 complete，`complete(false)` 以免有人永久等待。
- 文件不得超过 ~200 行。

- [ ] **Step 4: 跑测试确认通过**

```bash
cd client && flutter test test/services/stt/aliyun_stt_provider_test.dart
```

预期：`All tests passed!`，15 个测试。

- [ ] **Step 5: 跑整个 stt 目录并提交**

```bash
cd client && flutter test test/services/stt/
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd /Users/yitouxiaomaolv/git/cmux && git add \
  client/lib/services/stt/aliyun_stt_provider.dart \
  client/test/services/stt/aliyun_stt_provider_test.dart && \
git commit -m "feat(voice): add Alibaba NLS STT provider

PCM is dropped, not buffered, until TranscriptionStarted arrives: sending
early makes the gateway drop the task with no error, and replaying the
handshake-era audio afterwards would recognize a shifted sentence."
```

---

### Task 7: 偏好与凭据仓库、语言表

**Files:**
- Create: `client/lib/repositories/voice_input_repository.dart`
- Create: `client/lib/services/stt/stt_locales.dart`
- Modify: `client/lib/repositories/ssh_credential_store.dart`（追加 `InMemorySecureKeyValueStore`）
- Test: `client/test/repositories/voice_input_repository_test.dart`

**Interfaces:**
- Consumes: `SttProviderType`（Task 1）；`SpeechLocale`（Task 4）；既有 `SecureKeyValueStore`（`lib/repositories/ssh_credential_store.dart:14`）。
- Produces:
  - `enum VoiceCredentialField { volcAppId, volcAccessToken, aliyunAccessKeyId, aliyunAccessKeySecret, aliyunAppKey }`
  - `class VoiceInputPrefs` — `const VoiceInputPrefs({required SttProviderType provider, required String localeId})`、`static const defaults`、`copyWith`、`toJson`、`fromJson`
  - `class VoiceCredentials` — 五个 `String` 字段（`volcAppId`、`volcAccessToken`、`aliyunAccessKeyId`、`aliyunAccessKeySecret`、`aliyunAppKey`）、`static const empty`、`bool get hasVolcengine`、`bool get hasAliyun`、`bool hasFor(SttProviderType type)`、`String field(VoiceCredentialField f)`、`VoiceCredentials withField(VoiceCredentialField f, String value)`
  - `abstract class VoiceInputRepository` — `Future<VoiceInputPrefs> loadPrefs()`、`Future<void> savePrefs(VoiceInputPrefs prefs)`、`Future<VoiceCredentials> loadCredentials()`、`Future<void> saveCredential(VoiceCredentialField field, String value)`
  - `class DefaultVoiceInputRepository implements VoiceInputRepository` — 构造 `DefaultVoiceInputRepository({required SharedPreferences preferences, required SecureKeyValueStore secureStore})`、`static const storageKey = 'teampilot.voice_input.v1'`
  - `class InMemoryVoiceInputRepository implements VoiceInputRepository` — 暴露 `VoiceInputPrefs? lastSavedPrefs`、`int savePrefsCount`
  - `class InMemorySecureKeyValueStore implements SecureKeyValueStore`
  - `List<SpeechLocale> sttLocalesFor(SttProviderType type)`

**凭据键（必须逐字一致，改了会让已配置的用户凭据凭空消失）：** 前缀 `teampilot.voice_creds.v1`，字段名依次 `volc_app_id`、`volc_access_token`、`aliyun_access_key_id`、`aliyun_access_key_secret`、`aliyun_app_key`，完整键为 `<前缀>.<字段名>`。

- [ ] **Step 1: 写 `voice_input_repository_test.dart`**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/voice_input_repository.dart';
import 'package:teampilot/services/stt/stt_provider.dart';

void main() {
  late SharedPreferences preferences;
  late InMemorySecureKeyValueStore secureStore;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    secureStore = InMemorySecureKeyValueStore();
  });

  DefaultVoiceInputRepository build() => DefaultVoiceInputRepository(
    preferences: preferences,
    secureStore: secureStore,
  );

  group('prefs', () {
    test('defaults to the system provider and no explicit locale', () async {
      final prefs = await build().loadPrefs();
      expect(prefs.provider, SttProviderType.system);
      expect(prefs.localeId, '');
    });

    test('round-trips through storage', () async {
      await build().savePrefs(
        const VoiceInputPrefs(
          provider: SttProviderType.aliyun,
          localeId: 'zh-CN',
        ),
      );
      final reloaded = await build().loadPrefs();
      expect(reloaded.provider, SttProviderType.aliyun);
      expect(reloaded.localeId, 'zh-CN');
    });

    test('falls back to system for an unknown provider name', () async {
      // A downgrade, or a provider dropped in a later version, must not brick
      // voice input — it degrades to the backend that needs no credentials.
      await preferences.setString(
        DefaultVoiceInputRepository.storageKey,
        '{"provider":"tencent","localeId":"zh-CN"}',
      );
      final prefs = await build().loadPrefs();
      expect(prefs.provider, SttProviderType.system);
      expect(prefs.localeId, 'zh-CN', reason: 'the readable half survives');
    });

    test('falls back to defaults on unparseable JSON', () async {
      await preferences.setString(
        DefaultVoiceInputRepository.storageKey,
        'not json',
      );
      final prefs = await build().loadPrefs();
      expect(prefs.provider, SttProviderType.system);
      expect(prefs.localeId, '');
    });
  });

  group('credentials', () {
    test('start out empty', () async {
      final credentials = await build().loadCredentials();
      expect(credentials, VoiceCredentials.empty);
      expect(credentials.hasVolcengine, isFalse);
      expect(credentials.hasAliyun, isFalse);
    });

    test('write to the documented secure-storage keys', () async {
      final repository = build();
      await repository.saveCredential(VoiceCredentialField.volcAppId, 'app');
      await repository.saveCredential(
        VoiceCredentialField.aliyunAppKey,
        'key',
      );
      // Pinned literally: renaming a key silently loses the credential a user
      // already typed, and the failure looks like a broken provider.
      expect(
        await secureStore.read('teampilot.voice_creds.v1.volc_app_id'),
        'app',
      );
      expect(
        await secureStore.read('teampilot.voice_creds.v1.aliyun_app_key'),
        'key',
      );
    });

    test('load every field back', () async {
      final repository = build();
      for (final field in VoiceCredentialField.values) {
        await repository.saveCredential(field, field.name);
      }
      final credentials = await repository.loadCredentials();
      for (final field in VoiceCredentialField.values) {
        expect(credentials.field(field), field.name);
      }
    });

    test('deletes the entry when a field is cleared', () async {
      // Leaving an empty string behind would keep a dead keychain entry around
      // after the user deliberately removed a secret.
      final repository = build();
      await repository.saveCredential(VoiceCredentialField.volcAppId, 'app');
      await repository.saveCredential(VoiceCredentialField.volcAppId, '');
      expect(
        await secureStore.read('teampilot.voice_creds.v1.volc_app_id'),
        isNull,
      );
    });
  });

  group('VoiceCredentials.hasFor', () {
    test('system needs nothing', () {
      expect(VoiceCredentials.empty.hasFor(SttProviderType.system), isTrue);
    });

    test('volcengine needs both its fields', () {
      var credentials = VoiceCredentials.empty.withField(
        VoiceCredentialField.volcAppId,
        'app',
      );
      expect(credentials.hasFor(SttProviderType.volcengine), isFalse);
      credentials = credentials.withField(
        VoiceCredentialField.volcAccessToken,
        'token',
      );
      expect(credentials.hasFor(SttProviderType.volcengine), isTrue);
    });

    test('aliyun needs all three of its fields', () {
      var credentials = VoiceCredentials.empty
          .withField(VoiceCredentialField.aliyunAccessKeyId, 'id')
          .withField(VoiceCredentialField.aliyunAccessKeySecret, 'secret');
      expect(credentials.hasFor(SttProviderType.aliyun), isFalse);
      credentials = credentials.withField(
        VoiceCredentialField.aliyunAppKey,
        'key',
      );
      expect(credentials.hasFor(SttProviderType.aliyun), isTrue);
    });
  });

  group('sttLocalesFor', () {
    test('offers locales for every provider', () {
      for (final type in SttProviderType.values) {
        expect(sttLocalesFor(type), isNotEmpty, reason: type.name);
      }
    });

    test('has no duplicate ids within a provider', () {
      for (final type in SttProviderType.values) {
        final ids = sttLocalesFor(type).map((l) => l.id).toList();
        expect(ids.toSet(), hasLength(ids.length), reason: type.name);
      }
    });

    test('returns unmodifiable lists', () {
      // The picker holds onto whatever it is handed; a caller mutating this
      // would corrupt the table for every later open.
      expect(
        () => sttLocalesFor(SttProviderType.aliyun).add(
          const SpeechLocale(id: 'x', name: 'x'),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
```

`sttLocalesFor` 与 `SpeechLocale` 的 import：测试里从 `package:teampilot/services/stt/stt_locales.dart` 与 `package:teampilot/services/stt/speech_recognizer.dart` 取，按需补 import 行。

- [ ] **Step 2: 跑测试确认失败**

```bash
cd client && flutter test test/repositories/voice_input_repository_test.dart
```

预期：`Target of URI doesn't exist: 'package:teampilot/repositories/voice_input_repository.dart'`。

- [ ] **Step 3: 在 `ssh_credential_store.dart` 末尾追加**

```dart
/// Test double for [SecureKeyValueStore].
///
/// Lives here beside [InMemorySshCredentialStore] so both fakes for this file's
/// abstractions stay in one place.
class InMemorySecureKeyValueStore implements SecureKeyValueStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
```

- [ ] **Step 4: 写 `stt_locales.dart`**

```dart
import 'stt_provider.dart';
import 'speech_recognizer.dart';

/// Fallback list for on-device recognition, used when the platform cannot
/// enumerate its own locales.
const _systemFallback = <SpeechLocale>[
  SpeechLocale(id: 'zh_CN', name: '简体中文'),
  SpeechLocale(id: 'en_US', name: 'English (US)'),
  SpeechLocale(id: 'en_GB', name: 'English (UK)'),
  SpeechLocale(id: 'ja_JP', name: '日本語'),
  SpeechLocale(id: 'ko_KR', name: '한국어'),
  SpeechLocale(id: 'fr_FR', name: 'Français'),
  SpeechLocale(id: 'de_DE', name: 'Deutsch'),
  SpeechLocale(id: 'es_ES', name: 'Español'),
  SpeechLocale(id: 'ru_RU', name: 'Русский'),
  SpeechLocale(id: 'pt_BR', name: 'Português (BR)'),
];

/// Volcengine's supported recognition languages.
const _volcengine = <SpeechLocale>[
  SpeechLocale(id: 'zh-CN', name: '简体中文'),
  SpeechLocale(id: 'en-US', name: 'English (US)'),
  SpeechLocale(id: 'ja-JP', name: '日本語'),
  SpeechLocale(id: 'ko-KR', name: '한국어'),
];

/// Alibaba NLS's supported recognition languages.
const _aliyun = <SpeechLocale>[
  SpeechLocale(id: 'zh-CN', name: '简体中文'),
  SpeechLocale(id: 'zh-HK', name: '粤语'),
  SpeechLocale(id: 'en-US', name: 'English (US)'),
  SpeechLocale(id: 'ja-JP', name: '日本語'),
  SpeechLocale(id: 'ko-KR', name: '한국어'),
  SpeechLocale(id: 'ru-RU', name: 'Русский'),
  SpeechLocale(id: 'id-ID', name: 'Bahasa Indonesia'),
];

/// The languages [type] can recognize.
///
/// Language names stay in their own language rather than going through l10n: a
/// picker that renders every entry in the current UI locale is harder to scan
/// than one where each row reads as the language it selects.
List<SpeechLocale> sttLocalesFor(SttProviderType type) => List.unmodifiable(
  switch (type) {
    SttProviderType.system => _systemFallback,
    SttProviderType.volcengine => _volcengine,
    SttProviderType.aliyun => _aliyun,
  },
);
```

- [ ] **Step 5: 写 `voice_input_repository.dart`**

要求：

- `VoiceInputPrefs.toJson()` → `{'provider': provider.name, 'localeId': localeId}`。`fromJson` 按 `SttProviderType.values.firstWhere((t) => t.name == raw, orElse: () => SttProviderType.system)` 解析，`localeId` 取不到时用 `''`。
- `static const defaults = VoiceInputPrefs(provider: SttProviderType.system, localeId: '')`。
- `VoiceInputPrefs` 与 `VoiceCredentials` 都实现 `==` 与 `hashCode`（测试用 `expect(credentials, VoiceCredentials.empty)` 比的是值）。用 `Object.hash`，不引入 `equatable`（仓内两种写法都有，纯值类手写更省一层）。
- `VoiceCredentials.field(f)` 与 `withField(f, v)` 用 `switch (f)` 穷举五个枚举值，不写 `default` —— 以后加字段时编译器直接报错，比运行时漏掉好。
- `DefaultVoiceInputRepository.loadPrefs()` 读 `preferences.getString(storageKey)`，`jsonDecode` 的 `FormatException` 用 `on FormatException catch (e, st)` 捕获，`AppLogger.instance.w('Discarding unparseable voice input prefs at $storageKey ($e)', error: e, stackTrace: st)` 后返回 `VoiceInputPrefs.defaults`。照抄 `mobile_toolbar_repository.dart:129` 的写法与语气。
- `saveCredential(field, value)`：`value.isEmpty` 时 `secureStore.delete(key)`，否则 `write`。
- `loadCredentials()` 五个键并发读（`await Future.wait`），缺失作 `''`。
- `InMemoryVoiceInputRepository` 持有一份 `VoiceInputPrefs` 与一份 `VoiceCredentials`，`savePrefs` 递增 `savePrefsCount` 并记 `lastSavedPrefs`。

- [ ] **Step 6: 跑测试确认通过**

```bash
cd client && flutter test test/repositories/voice_input_repository_test.dart
```

预期：`All tests passed!`，14 个测试。

- [ ] **Step 7: analyze 并提交**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd /Users/yitouxiaomaolv/git/cmux && git add \
  client/lib/repositories/voice_input_repository.dart \
  client/lib/repositories/ssh_credential_store.dart \
  client/lib/services/stt/stt_locales.dart \
  client/test/repositories/voice_input_repository_test.dart && \
git commit -m "feat(voice): add voice input prefs, credential store and locales

Secrets go to the keychain through the existing SecureKeyValueStore;
clearing a field deletes the entry rather than storing an empty string. An
unknown persisted provider name degrades to the system recognizer, which
needs no credentials."
```

---

### Task 8: VoiceInputCubit

**Files:**
- Create: `client/lib/cubits/voice_input_cubit.dart`
- Test: `client/test/cubits/voice_input_cubit_test.dart`

**Interfaces:**
- Consumes: `SttProvider`、`SttResult`、`SttProviderType`、`SttException`、`VoicePermissionDeniedException`（Task 1）；`VoiceInputRepository`、`VoiceInputPrefs`、`VoiceCredentials`、`VoiceCredentialField`、`InMemoryVoiceInputRepository`（Task 7）。
- Produces:
  - `enum VoiceInputStatus { idle, starting, listening }`
  - `enum VoiceInputFailure { permissionDenied, failed }`
  - `class VoiceInputState` — 字段 `SttProviderType provider`、`String localeId`、`VoiceInputStatus status`、`VoiceCredentials credentials`、`bool systemAvailable`；getter `bool get configured`、`bool get available`；`copyWith`
  - `class VoiceInputCubit extends Cubit<VoiceInputState>` — 构造 `VoiceInputCubit({required VoiceInputRepository repository, required SttProvider Function(SttProviderType type, VoiceCredentials credentials) providerFactory, Duration maxDuration = const Duration(seconds: 60)})`；getter `Stream<String> get transcripts`、`Stream<VoiceInputFailure> get failures`；方法 `Future<void> load()`、`Future<void> startListening()`、`Future<void> stopListening()`、`Future<void> setProvider(SttProviderType type)`、`Future<void> setLocaleId(String localeId)`、`Future<void> setCredential(VoiceCredentialField field, String value)`、`Future<int> testConnection()`

**识别文本与失败都走 broadcast 流，不走注入回调。** 两者都是一次性事件而非状态：文本要写进别人持有的 `TextEditingController`，失败要弹 snackbar（需要 `BuildContext`，且可能在面板已卸载后才到 —— 用户关了面板，网络才超时）。放进 state 会让每条识别结果都 emit 一次，Composer 每识别一个词重画一次；做成构造回调则 cubit 必须在知道消费者之后才能创建，而它活在 pairing shell 层，比镜像页和 Composer 都长寿。流让消费者自行订阅，创建顺序就不再是约束。

两者都用 `StreamController<T>.broadcast()`，在 `close()` 里关闭。

**派生 getter 的语义：**
- `configured` = `provider == SttProviderType.system ? systemAvailable : credentials.hasFor(provider)`
- `available` = `systemAvailable || credentials.hasVolcengine || credentials.hasAliyun`

写成 getter 而非字段，是为了不可能出现两者与源数据不同步的状态。

- [ ] **Step 1: 写共享测试替身，再写 cubit 测试**

`FakeSttProvider` 放 `client/test/support/fake_stt_provider.dart` —— Task 9、10 的 widget test 也要用，塞在单个测试文件里就得跨文件相对 import。

`client/test/support/fake_stt_provider.dart` 的内容是下面 `FakeSttProvider` 这个类，加上文件头 `import 'dart:async';` 与 `import 'package:teampilot/services/stt/stt_provider.dart';`。

`client/test/cubits/voice_input_cubit_test.dart` 的头部为：

```dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/voice_input_cubit.dart';
import 'package:teampilot/repositories/voice_input_repository.dart';
import 'package:teampilot/services/stt/stt_provider.dart';

import '../support/fake_stt_provider.dart';
```

替身类（写进 `test/support/fake_stt_provider.dart`）：

```dart
/// A provider the test drives: [emit] pushes results, [openSession] resolves
/// `ready`.
class FakeSttProvider implements SttProvider {
  FakeSttProvider({this.availableValue = true, this.readyValue = true});

  final bool availableValue;
  final bool readyValue;

  final _results = StreamController<SttResult>.broadcast();
  final _ready = Completer<bool>();

  int startCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  String? startedLocaleId;
  int testConnectionMillis = 42;
  Object? testConnectionError;

  @override
  Future<bool> isAvailable() async => availableValue;

  @override
  Stream<SttResult> start({String? localeId}) {
    startCalls++;
    startedLocaleId = localeId;
    if (readyValue) {
      openSession();
    } else {
      if (!_ready.isCompleted) _ready.complete(false);
    }
    return _results.stream;
  }

  @override
  Future<bool> get ready => _ready.future;

  @override
  Future<void> stop() async {
    stopCalls++;
    if (!_results.isClosed) await _results.close();
  }

  @override
  Future<int> testConnection() async {
    final error = testConnectionError;
    if (error != null) throw error;
    return testConnectionMillis;
  }

  @override
  void dispose() => disposeCalls++;

  void openSession() {
    if (!_ready.isCompleted) _ready.complete(true);
  }

  void emit(String text, {required bool isFinal}) =>
      _results.add(SttResult(text: text, isFinal: isFinal));

  void fail(Object error) => _results.addError(error);

  Future<void> endSession() async {
    if (!_results.isClosed) await _results.close();
  }
}
```

测试主体（写进 `test/cubits/voice_input_cubit_test.dart`，接在上面那段 import 之后）：

```dart
void main() {
  late InMemoryVoiceInputRepository repository;
  late List<String> transcripts;
  late List<VoiceInputFailure> failures;
  late FakeSttProvider provider;
  late List<SttProviderType> builtFor;

  VoiceInputCubit build({
    FakeSttProvider? withProvider,
    Duration maxDuration = const Duration(seconds: 60),
  }) {
    provider = withProvider ?? FakeSttProvider();
    final cubit = VoiceInputCubit(
      repository: repository,
      providerFactory: (type, credentials) {
        builtFor.add(type);
        return provider;
      },
      maxDuration: maxDuration,
    );
    // Both are broadcast, so subscribing here does not stop the production
    // consumers (the mirror page and the failure messenger) from subscribing.
    cubit.transcripts.listen(transcripts.add);
    cubit.failures.listen(failures.add);
    return cubit;
  }

  setUp(() {
    repository = InMemoryVoiceInputRepository();
    transcripts = [];
    failures = [];
    builtFor = [];
  });

  group('load', () {
    test('starts idle on the system provider', () async {
      final cubit = build();
      await cubit.load();
      expect(cubit.state.provider, SttProviderType.system);
      expect(cubit.state.status, VoiceInputStatus.idle);
      expect(cubit.state.systemAvailable, isTrue);
      expect(cubit.state.available, isTrue);
      expect(cubit.state.configured, isTrue);
      await cubit.close();
    });

    test('is unavailable when nothing can run', () async {
      // No on-device recognizer and no cloud credentials: the mic button hides
      // rather than offering a tap that can only fail.
      final cubit = build(
        withProvider: FakeSttProvider(availableValue: false),
      );
      await cubit.load();
      expect(cubit.state.systemAvailable, isFalse);
      expect(cubit.state.available, isFalse);
      await cubit.close();
    });

    test('is available but unconfigured on a cloud provider with no keys',
        () async {
      await repository.savePrefs(
        const VoiceInputPrefs(
          provider: SttProviderType.aliyun,
          localeId: '',
        ),
      );
      final cubit = build();
      await cubit.load();
      expect(cubit.state.provider, SttProviderType.aliyun);
      expect(cubit.state.configured, isFalse);
      expect(
        cubit.state.available,
        isTrue,
        reason: 'the system recognizer still works, so the button stays',
      );
      await cubit.close();
    });
  });

  group('listening', () {
    test('goes starting then listening, passing the chosen locale', () async {
      final cubit = build();
      await cubit.load();
      await cubit.setLocaleId('zh-CN');

      final starting = cubit.startListening();
      expect(cubit.state.status, VoiceInputStatus.starting);
      await starting;
      expect(cubit.state.status, VoiceInputStatus.listening);
      expect(provider.startedLocaleId, 'zh-CN');
      await cubit.close();
    });

    test('inserts only final results', () async {
      // Interim text is overwritten on the next frame; inserting it would leave
      // half-recognized fragments in the composer.
      final cubit = build();
      await cubit.load();
      await cubit.startListening();

      provider.emit('git', isFinal: false);
      provider.emit('git commit', isFinal: true);
      await Future<void>.delayed(Duration.zero);

      expect(transcripts, ['git commit']);
      await cubit.close();
    });

    test('inserts the last interim result if the session ends without a final',
        () async {
      // A short utterance can close before the backend settles a sentence;
      // dropping it would lose everything the user said.
      final cubit = build();
      await cubit.load();
      await cubit.startListening();

      provider.emit('ls -la', isFinal: false);
      await Future<void>.delayed(Duration.zero);
      await provider.endSession();
      await Future<void>.delayed(Duration.zero);

      expect(transcripts, ['ls -la']);
      expect(cubit.state.status, VoiceInputStatus.idle);
      await cubit.close();
    });

    test('does not re-insert an interim result already superseded by a final',
        () async {
      final cubit = build();
      await cubit.load();
      await cubit.startListening();

      provider.emit('git', isFinal: false);
      provider.emit('git commit', isFinal: true);
      await Future<void>.delayed(Duration.zero);
      await provider.endSession();
      await Future<void>.delayed(Duration.zero);

      expect(transcripts, ['git commit']);
      await cubit.close();
    });

    test('ignores a second start while already listening', () async {
      final cubit = build();
      await cubit.load();
      await cubit.startListening();
      await cubit.startListening();
      expect(provider.startCalls, 1);
      await cubit.close();
    });

    test('returns to idle and stops the provider on stopListening', () async {
      final cubit = build();
      await cubit.load();
      await cubit.startListening();
      await cubit.stopListening();
      expect(cubit.state.status, VoiceInputStatus.idle);
      expect(provider.stopCalls, 1);
      await cubit.close();
    });

    test('stopListening is safe when idle', () async {
      final cubit = build();
      await cubit.load();
      await expectLater(cubit.stopListening(), completes);
      expect(provider.stopCalls, 0);
      await cubit.close();
    });

    test('returns to idle when the session never becomes ready', () async {
      final cubit = build(withProvider: FakeSttProvider(readyValue: false));
      await cubit.load();
      await cubit.startListening();
      expect(cubit.state.status, VoiceInputStatus.idle);
      await cubit.close();
    });
  });

  group('failures', () {
    test('reports a denied microphone as its own failure', () async {
      final cubit = build();
      await cubit.load();
      await cubit.startListening();

      provider.fail(const VoicePermissionDeniedException());
      await Future<void>.delayed(Duration.zero);

      expect(failures, [VoiceInputFailure.permissionDenied]);
      expect(cubit.state.status, VoiceInputStatus.idle);
      await cubit.close();
    });

    test('reports any other error as a generic failure', () async {
      final cubit = build();
      await cubit.load();
      await cubit.startListening();

      provider.fail(const SttException('socket died'));
      await Future<void>.delayed(Duration.zero);

      expect(failures, [VoiceInputFailure.failed]);
      expect(cubit.state.status, VoiceInputStatus.idle);
      await cubit.close();
    });
  });

  group('settings', () {
    test('setProvider persists and rebuilds on the next session', () async {
      final cubit = build();
      await cubit.load();
      await cubit.setProvider(SttProviderType.volcengine);
      expect(cubit.state.provider, SttProviderType.volcengine);
      expect(repository.lastSavedPrefs!.provider, SttProviderType.volcengine);
      await cubit.startListening();
      expect(builtFor.last, SttProviderType.volcengine);
      await cubit.close();
    });

    test('setProvider stops an in-flight session first', () async {
      // Switching backends mid-utterance would leave the old socket streaming
      // audio the user thinks they redirected.
      final cubit = build();
      await cubit.load();
      await cubit.startListening();
      await cubit.setProvider(SttProviderType.aliyun);
      expect(provider.stopCalls, 1);
      expect(cubit.state.status, VoiceInputStatus.idle);
      await cubit.close();
    });

    test('setCredential persists and updates configured', () async {
      final cubit = build();
      await cubit.load();
      await cubit.setProvider(SttProviderType.volcengine);
      expect(cubit.state.configured, isFalse);

      await cubit.setCredential(VoiceCredentialField.volcAppId, 'app');
      await cubit.setCredential(
        VoiceCredentialField.volcAccessToken,
        'token',
      );

      expect(cubit.state.configured, isTrue);
      expect(cubit.state.credentials.volcAppId, 'app');
      await cubit.close();
    });

    test('testConnection returns the provider latency', () async {
      final cubit = build();
      await cubit.load();
      expect(await cubit.testConnection(), 42);
      await cubit.close();
    });

    test('testConnection propagates the failure', () async {
      final cubit = build();
      await cubit.load();
      provider.testConnectionError = const SttException('bad key');
      await expectLater(
        cubit.testConnection(),
        throwsA(isA<SttException>()),
      );
      await cubit.close();
    });
  });

  test('auto-stops at the recording cap', () {
    // A mic left open is metered cloud spend and an open privacy hole; nothing
    // dictated into a terminal runs a minute.
    fakeAsync((async) {
      final cubit = build(maxDuration: const Duration(seconds: 60));
      cubit.load();
      async.flushMicrotasks();
      cubit.startListening();
      async.flushMicrotasks();
      expect(cubit.state.status, VoiceInputStatus.listening);

      async.elapse(const Duration(seconds: 59));
      expect(cubit.state.status, VoiceInputStatus.listening);

      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(cubit.state.status, VoiceInputStatus.idle);
      expect(provider.stopCalls, 1);

      cubit.close();
      async.flushMicrotasks();
    });
  });

  test('close stops an in-flight session', () async {
    // Leaving the mirror page must not leave the microphone hot.
    final cubit = build();
    await cubit.load();
    await cubit.startListening();
    await cubit.close();
    expect(provider.stopCalls, 1);
  });

  test('load after close does not emit', () async {
    final cubit = build();
    await cubit.close();
    await expectLater(cubit.load(), completes);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

```bash
cd client && flutter test test/cubits/voice_input_cubit_test.dart
```

预期：`Target of URI doesn't exist: 'package:teampilot/cubits/voice_input_cubit.dart'`。

- [ ] **Step 3: 写 `voice_input_cubit.dart`**

要求，逐条照做：

- `VoiceInputState` 手写 `copyWith`，**不需要** `==`（`status` 变化就该重画；但 UI 侧的 `BlocBuilder` 必须用 `buildWhen`，见 Task 9）。
- `load()`：`await repository.loadPrefs()` 与 `loadCredentials()`；再用 `providerFactory(SttProviderType.system, credentials).isAvailable()` 探系统可用性，探完 `dispose()` 掉这个临时 provider。**每次 `await` 之后判 `if (isClosed) return;`**。
- `_session` 字段保存当前 `SttProvider?`、`StreamSubscription<SttResult>?`、`Timer?`（录音上限）、`String? _lastPartial`、`bool _insertedFinal`。
- `startListening()`：
  1. `if (state.status != VoiceInputStatus.idle) return;`
  2. `if (!state.configured) return;` —— **未配置时 cubit 不动作**，推设置页由 UI 负责（cubit 不认识 Navigator）。
  3. `emit(state.copyWith(status: VoiceInputStatus.starting))`
  4. 建 provider、订阅 `start(localeId: state.localeId.isEmpty ? null : state.localeId)` 的流：`onData` 里 final 则往 `_transcripts` 加 `text` 并置 `_insertedFinal = true`、清 `_lastPartial`；非 final 则记 `_lastPartial = text`。`onError` 走 `_finishWithFailure`。`onDone` 走 `_finishNaturally`（若 `!_insertedFinal` 且 `_lastPartial` 非空则补插）。
  5. `if (!await provider.ready) { await _teardown(); emit(idle); return; }`
  6. `if (isClosed) { await _teardown(); return; }`
  7. `emit(state.copyWith(status: VoiceInputStatus.listening))`，起 `Timer(maxDuration, stopListening)`。
- `_finishWithFailure(Object error)`：往 `_failures` 加 `error is VoicePermissionDeniedException ? VoiceInputFailure.permissionDenied : VoiceInputFailure.failed`；`AppLogger.instance.w('Voice input failed ($error)', error: error, stackTrace: st)`；`_teardown()`；`emit(idle)`。**先 teardown 再 emit**，否则 UI 可能在 provider 还活着时又允许一次 tap。
- `stopListening()`：`_session == null` 则直接 return；取消 timer、`await provider.stop()`、取消订阅、`provider.dispose()`、清字段、`emit(idle)`。幂等。
- `setProvider` / `setLocaleId`：先 `await stopListening()`，再 emit 新值，再 `repository.savePrefs(...)`。
- `setCredential(field, value)`：`await repository.saveCredential(field, value)`，再 `emit(state.copyWith(credentials: state.credentials.withField(field, value)))`。
- `testConnection()`：临时建一个当前 provider，`try { return await p.testConnection(); } finally { p.dispose(); }`。不改 `status`。
- `close()`：`await stopListening()` 包在 `try` 里，然后关闭 `_transcripts` 与 `_failures`，`finally { await super.close(); }`。**注意 A 期教训**：只 await 本调用自己发起的异步；不要 await 定时器回调里创建的 future。
- 文件不得超过 ~300 行。

- [ ] **Step 4: 跑测试确认通过**

```bash
cd client && flutter test test/cubits/voice_input_cubit_test.dart
```

预期：`All tests passed!`，22 个测试。若 `auto-stops at the recording cap` 挂在超时上，先确认 `close()` 没有 await 定时器里创建的 future —— A 期同样的坑吃掉了整整一个 subagent 的预算。

- [ ] **Step 5: analyze 并提交**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd /Users/yitouxiaomaolv/git/cmux && git add \
  client/lib/cubits/voice_input_cubit.dart \
  client/test/support/fake_stt_provider.dart \
  client/test/cubits/voice_input_cubit_test.dart && \
git commit -m "feat(voice): add VoiceInputCubit

Only final results reach the composer, with the last interim kept as a
fallback for an utterance that ends before the backend settles it. A
session tears down before the state says idle, and a 60s timer caps an
open microphone."
```

---

### Task 9: Composer 麦克风按钮与镜像页接线

**Files:**
- Modify: `client/lib/pages/pairing/mobile_toolbar/mobile_composer_panel.dart`
- Create: `client/lib/pages/pairing/mobile_toolbar/voice_failure_messenger.dart`
- Create: `client/lib/services/stt/stt_provider_factory.dart`
- Modify: `client/lib/pages/pairing/pairing_mobile_shell.dart`
- Modify: `client/lib/pages/pairing/pairing_mirror_page.dart`
- Modify: `client/lib/utils/ui/app_keys.dart`
- Modify: `client/lib/l10n/app_en.arb`、`client/lib/l10n/app_zh.arb`
- Modify: `client/test/pages/pairing/mobile_bottom_slot_test.dart`、`client/test/pages/pairing/mobile_composer_panel_test.dart`（只加 provider 包裹，断言一律不改）
- Test: `client/test/pages/pairing/composer_mic_button_test.dart`

**Interfaces:**
- Consumes: `VoiceInputCubit`、`VoiceInputState`、`VoiceInputStatus`、`VoiceInputFailure`（Task 8）；`SttProviderType`（Task 1）；`insertTranscript`（Task 1）；`DefaultVoiceInputRepository`（Task 7）；`FakeSttProvider`（Task 8 的 `test/support/fake_stt_provider.dart`）。
- Produces: `AppKeys.mobileComposerMicButton`；7 条 l10n 键。

**本任务新增的 l10n 键**（两个 ARB 都加，无 placeholder）：

| key | en | zh |
|---|---|---|
| `voiceInputStart` | Start dictation | 开始语音输入 |
| `voiceInputStop` | Stop dictation | 停止语音输入 |
| `voiceInputBadgeSystem` | SYS | 系统 |
| `voiceInputBadgeVolcengine` | DOU | 豆包 |
| `voiceInputBadgeAliyun` | ALI | 阿里 |
| `voiceInputPermissionDenied` | Microphone access denied. Enable it in system settings. | 麦克风权限被拒绝，请在系统设置中开启 |
| `voiceInputFailed` | Voice input failed | 语音输入失败 |

**面板现在要求 scope 里有 `VoiceInputCubit`。** 这会让 B 期两个已有测试报 `ProviderNotFoundException`，所以本任务要给它们加 `MultiBlocProvider` 包裹。**断言、测试名、注释一个字都不许改** —— 它们钉的是 B 期已确认的行为，只是多了一个依赖要提供。

- [ ] **Step 1: 加 l10n 与 app_keys**

`client/lib/l10n/app_en.arb` 与 `app_zh.arb` 各加上表 7 条，放在既有 `mobileComposer*` 键之后，保持文件里的平铺 camelCase 风格。

`client/lib/utils/ui/app_keys.dart`，接在 `mobileComposerSubmitToggle` 那行之后：

```dart
  static const mobileComposerMicButton = Key('mobile-composer-mic');
```

- [ ] **Step 2: 重新生成 l10n**

```bash
cd client && flutter gen-l10n && dart run tool/gen_warmup_glyphs.dart
```

预期：两条命令都成功；`git status --short client/lib/l10n` 显示生成的 `app_localizations*.dart` 与 `warmup_glyphs.g.dart` 有改动。A、B 期都遇到过生成产物落后于 ARB，先跑这一步再写引用它的代码，能省一轮编译失败。

- [ ] **Step 3: 写 `composer_mic_button_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/mobile_toolbar_cubit.dart';
import 'package:teampilot/cubits/voice_input_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/pairing/mobile_toolbar/mobile_composer_panel.dart';
import 'package:teampilot/repositories/mobile_toolbar_repository.dart';
import 'package:teampilot/repositories/voice_input_repository.dart';
import 'package:teampilot/services/stt/stt_provider.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/fake_stt_provider.dart';

void main() {
  late MobileToolbarCubit toolbar;
  late VoiceInputCubit voice;
  late InMemoryVoiceInputRepository voiceRepository;
  late FakeSttProvider provider;
  late TextEditingController controller;
  late FocusNode focusNode;

  setUp(() {
    toolbar = MobileToolbarCubit(
      repository: InMemoryMobileToolbarRepository(),
      sendInput: (_) {},
      readClipboard: () async => null,
      usageFlushDelay: const Duration(milliseconds: 10),
    );
    voiceRepository = InMemoryVoiceInputRepository();
    provider = FakeSttProvider();
    voice = VoiceInputCubit(
      repository: voiceRepository,
      providerFactory: (_, _) => provider,
    );
    controller = TextEditingController();
    focusNode = FocusNode();
  });

  tearDown(() async {
    await voice.close();
    await toolbar.close();
    controller.dispose();
    focusNode.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox.expand()),
              MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: toolbar),
                  BlocProvider.value(value: voice),
                ],
                child: MobileComposerPanel(
                  controller: controller,
                  focusNode: focusNode,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the mic once a backend is available', (t) async {
    await voice.load();
    await pump(t);
    expect(find.byKey(AppKeys.mobileComposerMicButton), findsOneWidget);
  });

  testWidgets('hides the mic when nothing can run', (t) async {
    // No on-device recognizer and no cloud keys: a tap could only ever fail, so
    // the button is not offered. The settings sheet still reaches the page.
    final unavailable = VoiceInputCubit(
      repository: InMemoryVoiceInputRepository(),
      providerFactory: (_, _) => FakeSttProvider(availableValue: false),
    );
    addTearDown(unavailable.close);
    await unavailable.load();
    voice = unavailable;
    await pump(t);
    expect(find.byKey(AppKeys.mobileComposerMicButton), findsNothing);
  });

  testWidgets('tapping the mic starts a session', (t) async {
    await voice.load();
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerMicButton));
    await t.pump();
    await t.pump();
    expect(provider.startCalls, 1);
    expect(voice.state.status, VoiceInputStatus.listening);
  });

  testWidgets('shows the listening icon while a session is live', (t) async {
    await voice.load();
    await pump(t);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);

    await t.tap(find.byKey(AppKeys.mobileComposerMicButton));
    await t.pump();
    await t.pump();

    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsNothing);
  });

  testWidgets('tapping again stops the session', (t) async {
    await voice.load();
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerMicButton));
    await t.pump();
    await t.pump();
    await t.tap(find.byKey(AppKeys.mobileComposerMicButton));
    await t.pump();
    await t.pump();
    expect(provider.stopCalls, 1);
    expect(voice.state.status, VoiceInputStatus.idle);
  });

  testWidgets('shows the provider badge', (t) async {
    await voiceRepository.savePrefs(
      const VoiceInputPrefs(provider: SttProviderType.volcengine, localeId: ''),
    );
    await voiceRepository.saveCredential(VoiceCredentialField.volcAppId, 'a');
    await voiceRepository.saveCredential(
      VoiceCredentialField.volcAccessToken,
      'b',
    );
    await voice.load();
    await pump(t);
    expect(find.text('DOU'), findsOneWidget);
  });

  testWidgets('closing the composer stops a live session', (t) async {
    // One of the four paths that must not leave the microphone hot.
    await voice.load();
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerMicButton));
    await t.pump();
    await t.pump();

    await t.tap(find.byKey(AppKeys.mobileComposerCloseButton));
    await t.pump();

    expect(provider.stopCalls, 1);
  });

  testWidgets('surfaces a denied microphone as a snack bar', (t) async {
    await voice.load();
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerMicButton));
    await t.pump();
    await t.pump();

    provider.fail(const VoicePermissionDeniedException());
    await t.pump();
    await t.pump();

    expect(
      find.text('Microphone access denied. Enable it in system settings.'),
      findsOneWidget,
    );
  });

  testWidgets('surfaces any other failure as a snack bar', (t) async {
    await voice.load();
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerMicButton));
    await t.pump();
    await t.pump();

    provider.fail(const SttException('socket died'));
    await t.pump();
    await t.pump();

    expect(find.text('Voice input failed'), findsOneWidget);
  });
}
```

- [ ] **Step 4: 跑测试确认失败**

```bash
cd client && flutter test test/pages/pairing/composer_mic_button_test.dart
```

预期：编译失败，`Undefined name 'mobileComposerMicButton'` 已在 Step 1 解决，所以真实失败应是 `ProviderNotFoundException` 或断言失败 —— 面板还没有麦克风按钮。

- [ ] **Step 5: 改 `mobile_composer_panel.dart`**

在 `const Spacer()`（现 :142）与发送按钮之间插入麦克风。要求：

- 新增私有 `_MicButton extends StatefulWidget`（脉冲环要 `AnimationController`，所以不能塞进现有的 `_CircleButton`），放在文件末尾 `_CircleButton` 之后。
- 面板的按钮行 `BlocBuilder` 的 `buildWhen` **不要动**（它盯的是 `chatMode`）。麦克风自己用一个独立的 `BlocBuilder<VoiceInputCubit, VoiceInputState>`，`buildWhen: (a, b) => a.status != b.status || a.available != b.available || a.provider != b.provider`。`VoiceInputState` 没有值相等，不加 `buildWhen` 每次 emit 都会重建脉冲动画。
- `state.available` 为假时该 `BlocBuilder` 返回 `const SizedBox.shrink()`。
- 三态：
  - `idle` → `_CircleButton(buttonKey: AppKeys.mobileComposerMicButton, icon: Icons.mic_none, tooltip: l10n.voiceInputStart, onTap: cubit.startListening)`。所选 provider 未配置时 `startListening()` 自身就会直接返回（Task 8 的守卫），所以本任务的 tap 行为对已配置/未配置一致；未配置时改推设置页是 Task 10 的事，设置页在那之前还不存在。
  - `starting` → 34×34 的 `Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))`，包在与 `_CircleButton` 同底色同圆角的容器里，`onTap` 为 null。
  - `listening` → `_CircleButton(icon: Icons.mic, filled: true, tooltip: l10n.voiceInputStop, onTap: cubit.stopListening)`，外层套脉冲环。
- 脉冲环：`AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat()`，`Stack` 里放一个 `IgnorePointer` 的 `Transform.scale(scale: lerpDouble(1.0, 1.8, t)!)` + `Opacity(opacity: lerpDouble(0.4, 0.0, t)!)` 的 `cs.primary` 圆。`listening` 之外不建控制器（在 `_MicButton` 内按 `status` 起停 `repeat()` / `stop()`）。`dispose` 里必须 `dispose()` 掉控制器。
- 角标：`Positioned(right: 0, top: 0)` 的小圆 `Text`，字号 8，文本按 `state.provider` 取 `l10n.voiceInputBadgeSystem` / `Volcengine` / `Aliyun`。
- 关闭按钮的 `onTap` 里，在现有 `FocusScope.of(context).unfocus()` 之前加一行 `context.read<VoiceInputCubit>().stopListening();`（不 await —— 回调是同步的，停止是 fire-and-forget）。注释写明这是麦克风必停的四条路径之一。
- 失败提示新建 `lib/pages/pairing/mobile_toolbar/voice_failure_messenger.dart`：

```dart
/// Turns [VoiceInputCubit.failures] into snack bars.
///
/// A widget rather than a `BlocListener` because a failure is an event, not
/// state — a recognition error leaves the cubit back at [VoiceInputStatus.idle],
/// which is indistinguishable from never having started.
class VoiceFailureMessenger extends StatefulWidget {
  const VoiceFailureMessenger({
    super.key,
    required this.failures,
    required this.child,
  });

  final Stream<VoiceInputFailure> failures;
  final Widget child;
  ...
}
```

`initState` 订阅 `widget.failures`，回调里 `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)))`，`message` 按 failure 取 `l10n.voiceInputPermissionDenied` / `l10n.voiceInputFailed`（订阅回调里要先判 `mounted`）。`dispose` 取消订阅。

- 面板的 `DecoratedBox` 外面包 `VoiceFailureMessenger(failures: context.read<VoiceInputCubit>().failures, child: …)`。这样 snackbar 逻辑在生产代码里，测试只断言结果。

- [ ] **Step 6: 在 pairing shell 提供 cubit，镜像页订阅**

`VoiceInputCubit` 建在 `client/lib/pages/pairing/pairing_mobile_shell.dart`，**不建在镜像页**。语音的 provider 选择与凭据是跨屏偏好，Task 10 的设置入口挂在主屏的设置 sheet 上（`paired_hosts_page.dart:102`），那里读不到镜像页里的 cubit；而镜像页每次进出都重建，会把已探好的可用性和刚读出的凭据丢掉重来。

`pairing_mobile_shell.dart`：用 `BlocProvider<VoiceInputCubit>` 包住 shell 现有的 `_buildPhase` 子树：

```dart
BlocProvider<VoiceInputCubit>(
  create: (context) => VoiceInputCubit(
    repository: DefaultVoiceInputRepository(
      preferences: context.read<SharedPreferences>(),
      secureStore: const FlutterSecureKeyValueStore(),
    ),
    providerFactory: buildSttProvider,
  )..load(),
  child: …,
)
```

`BlocProvider` 自己会在销毁时 `close()`，所以不需要手写 dispose。

`pairing_mirror_page.dart`：

- `initState` 里在 `_toolbar` 之后订阅识别文本：

```dart
    // Recognized speech goes into the composer's controller, not into cubit
    // state: a per-result emit would rebuild the panel on every spoken word.
    _transcripts = context.read<VoiceInputCubit>().transcripts.listen((text) {
      _composerText.value = insertTranscript(_composerText.value, text);
    });
```

字段 `StreamSubscription<String>? _transcripts;`。

- `dispose`：`_transcripts?.cancel();` 要排在 `_composerText.dispose()` **之前** —— 否则一条在途的识别结果会写进已销毁的 controller。同时加 `context.read<VoiceInputCubit>().stopListening();` **不行**（`dispose` 里不能 `context.read`），所以在 `initState` 里把 cubit 存进字段 `late final VoiceInputCubit _voice = context.read<VoiceInputCubit>();`，`dispose` 里 `_voice.stopListening();`。**只 `stopListening()`，不 `close()`** —— cubit 归 shell 所有，镜像页只借用。
- `build` 里底部的 `BlocProvider.value` 换成 `MultiBlocProvider`，同时提供 `_toolbar` 与 `_voice`（Composer 要读它）。
- `PopScope.onPopInvokedWithResult` 里在 `cubit.leaveMirror()` 之前加 `_voice.stopListening();`（第四条必停路径）。

`buildSttProvider` 是新增的工厂函数，放 `lib/services/stt/stt_provider_factory.dart`：

```dart
SttProvider buildSttProvider(SttProviderType type, VoiceCredentials creds) =>
    switch (type) {
      SttProviderType.system => SystemSttProvider(PluginSpeechRecognizer()),
      SttProviderType.volcengine => VolcengineSttProvider(
        audio: RecordPcmAudioSource(),
        socketFactory: WebSocketSttSocket.connect,
        appId: creds.volcAppId,
        accessToken: creds.volcAccessToken,
        requestIdFactory: () => const Uuid().v4(),
      ),
      SttProviderType.aliyun => AliyunSttProvider(
        audio: RecordPcmAudioSource(),
        socketFactory: WebSocketSttSocket.connect,
        tokenService: AliyunTokenService(
          client: http.Client(),
          nonceFactory: () => const Uuid().v4(),
          now: DateTime.now,
        ),
        accessKeyId: creds.aliyunAccessKeyId,
        accessKeySecret: creds.aliyunAccessKeySecret,
        appKey: creds.aliyunAppKey,
        idFactory: () => const Uuid().v4().replaceAll('-', ''),
      ),
    };
```

`idFactory` 去掉连字符是因为阿里要 32 位 hex；`Uuid().v4()` 去掉 4 个连字符正好 32 位。

- [ ] **Step 7: 给 B 期两个测试加 provider 包裹**

`client/test/pages/pairing/mobile_bottom_slot_test.dart` 与 `client/test/pages/pairing/mobile_composer_panel_test.dart`：在 `setUp` 里加一个 `VoiceInputCubit`（`InMemoryVoiceInputRepository` + `FakeSttProvider`），`tearDown` 里 `close()`，把原来的 `BlocProvider.value(value: cubit, …)` 换成 `MultiBlocProvider`。**断言、测试名、注释一个字不改。** 若某条断言在加了麦克风按钮后失效（例如按钮数量或布局溢出），**不要改断言** —— 报告出来，这属于面板容量问题，要在实现侧解决（例如按钮间距）。

- [ ] **Step 8: 跑测试**

```bash
cd client && flutter test test/pages/pairing/ test/cubits/
```

预期：全绿。麦克风让按钮行多了一个 34pt 控件，A 期就遇到过第三个按钮把 `ctrl_c` 挤出 800pt 测试画布 —— 若有 widget 报 overflow，先在实现里收紧间距，再跑。

- [ ] **Step 9: analyze 并提交**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd /Users/yitouxiaomaolv/git/cmux && git add \
  client/lib/pages/pairing/mobile_toolbar/mobile_composer_panel.dart \
  client/lib/pages/pairing/mobile_toolbar/voice_failure_messenger.dart \
  client/lib/pages/pairing/pairing_mobile_shell.dart \
  client/lib/pages/pairing/pairing_mirror_page.dart \
  client/lib/services/stt/stt_provider_factory.dart \
  client/lib/utils/ui/app_keys.dart \
  client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations.dart \
  client/lib/l10n/app_localizations_en.dart \
  client/lib/l10n/app_localizations_zh.dart \
  client/lib/theme/warmup_glyphs.g.dart \
  client/test/pages/pairing/composer_mic_button_test.dart \
  client/test/pages/pairing/mobile_bottom_slot_test.dart \
  client/test/pages/pairing/mobile_composer_panel_test.dart && \
git commit -m "feat(voice): add the composer mic button

Three states rather than two: a cloud session spends a second or two
minting a token and shaking hands, and a button that looks idle through
that window reads as an unresponsive tap. Closing the composer and leaving
the mirror both stop the session — a hot mic outliving its panel is a
privacy problem, not a cosmetic one."
```

生成的 l10n 产物路径若与上面不同，用 `git status --short client/lib/l10n client/lib/theme` 查实际路径再 add。

---

### Task 10: 语音设置页

**Files:**
- Create: `client/lib/pages/pairing/voice/voice_settings_page.dart`
- Modify: `client/lib/pages/pairing/mobile_settings_sheet.dart`
- Modify: `client/lib/pages/pairing/mobile_toolbar/mobile_composer_panel.dart`（未配置时的 tap、长按）
- Modify: `client/lib/utils/ui/app_keys.dart`
- Modify: `client/lib/l10n/app_en.arb`、`client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/pairing/voice_settings_page_test.dart`

**Interfaces:**
- Consumes: `VoiceInputCubit`、`VoiceInputState`（Task 8）；`VoiceCredentialField`（Task 7）；`sttLocalesFor`、`SpeechLocale`（Task 7、4）；`SttProviderType`（Task 1）。
- Produces: `VoiceSettingsPage` 与 `static Route<void> route(VoiceInputCubit cubit)`；`AppKeys.voiceSettingsPage`、`voiceSettingsProviderTile(String)`、`voiceSettingsLanguageTile`、`voiceSettingsCredentialField(String)`、`voiceSettingsTestButton`、`mobileSettingsVoiceRow`；余下 17 条 l10n 键。

**本任务新增的 l10n 键**（两个 ARB 都加）：

| key | en | zh |
|---|---|---|
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
| `voiceInputCloudPrivacyNote` | Audio is sent directly to the cloud provider, not through the encrypted pairing channel. | 音频将直接发送给云服务商，不经过端到端加密的配对通道。 |

`voiceInputTestPassed` 需要 placeholder 元数据块：

```json
  "voiceInputTestPassed": "Connected in {ms} ms",
  "@voiceInputTestPassed": {
    "placeholders": {
      "ms": { "type": "int" }
    }
  },
```

- [ ] **Step 1: 加 l10n 与 app_keys，重新生成**

ARB 两个文件各加上表 17 条（`app_zh.arb` 不需要重复 `@` 元数据块，只有模板文件 `app_en.arb` 带）。`app_keys.dart` 加：

```dart
  static const voiceSettingsPage = Key('voice-settings-page');
  static Key voiceSettingsProviderTile(String provider) =>
      Key('voice-settings-provider-$provider');
  static const voiceSettingsLanguageTile = Key('voice-settings-language');
  static Key voiceSettingsCredentialField(String field) =>
      Key('voice-settings-credential-$field');
  static const voiceSettingsTestButton = Key('voice-settings-test');
  static const mobileSettingsVoiceRow = Key('mobile-settings-voice');
```

```bash
cd client && flutter gen-l10n && dart run tool/gen_warmup_glyphs.dart
```

- [ ] **Step 2: 写 `voice_settings_page_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/voice_input_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/pairing/voice/voice_settings_page.dart';
import 'package:teampilot/repositories/voice_input_repository.dart';
import 'package:teampilot/services/stt/stt_provider.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/fake_stt_provider.dart';

void main() {
  late InMemoryVoiceInputRepository repository;
  late VoiceInputCubit cubit;
  late FakeSttProvider provider;

  setUp(() {
    repository = InMemoryVoiceInputRepository();
    provider = FakeSttProvider();
    cubit = VoiceInputCubit(
      repository: repository,
      providerFactory: (_, _) => provider,
    );
  });

  tearDown(() => cubit.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider.value(
          value: cubit,
          child: const VoiceSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists every recognition service', (t) async {
    await cubit.load();
    await pump(t);
    expect(find.byKey(AppKeys.voiceSettingsPage), findsOneWidget);
    for (final type in SttProviderType.values) {
      expect(
        find.byKey(AppKeys.voiceSettingsProviderTile(type.name)),
        findsOneWidget,
        reason: type.name,
      );
    }
  });

  testWidgets('shows no credential fields for the system service', (t) async {
    await cubit.load();
    await pump(t);
    expect(
      find.byKey(AppKeys.voiceSettingsCredentialField('volcAppId')),
      findsNothing,
    );
    expect(find.byKey(AppKeys.voiceSettingsTestButton), findsNothing,
        reason: 'nothing to connect to');
  });

  testWidgets('picking Volcengine reveals its two fields and the test button',
      (t) async {
    await cubit.load();
    await pump(t);
    await t.tap(
      find.byKey(
        AppKeys.voiceSettingsProviderTile(SttProviderType.volcengine.name),
      ),
    );
    await t.pumpAndSettle();

    expect(cubit.state.provider, SttProviderType.volcengine);
    expect(repository.lastSavedPrefs!.provider, SttProviderType.volcengine);
    expect(
      find.byKey(AppKeys.voiceSettingsCredentialField('volcAppId')),
      findsOneWidget,
    );
    expect(
      find.byKey(AppKeys.voiceSettingsCredentialField('volcAccessToken')),
      findsOneWidget,
    );
    expect(find.byKey(AppKeys.voiceSettingsTestButton), findsOneWidget);
  });

  testWidgets('picking Alibaba reveals its three fields', (t) async {
    await cubit.load();
    await pump(t);
    await t.tap(
      find.byKey(
        AppKeys.voiceSettingsProviderTile(SttProviderType.aliyun.name),
      ),
    );
    await t.pumpAndSettle();

    for (final field in [
      'aliyunAccessKeyId',
      'aliyunAccessKeySecret',
      'aliyunAppKey',
    ]) {
      expect(
        find.byKey(AppKeys.voiceSettingsCredentialField(field)),
        findsOneWidget,
        reason: field,
      );
    }
  });

  testWidgets('typing a credential persists it on submit', (t) async {
    await cubit.load();
    await pump(t);
    await t.tap(
      find.byKey(
        AppKeys.voiceSettingsProviderTile(SttProviderType.volcengine.name),
      ),
    );
    await t.pumpAndSettle();

    await t.enterText(
      find.byKey(AppKeys.voiceSettingsCredentialField('volcAppId')),
      'the-app-id',
    );
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();

    expect(cubit.state.credentials.volcAppId, 'the-app-id');
  });

  testWidgets('obscures the secret fields but not the identifiers', (t) async {
    // An access token read over someone's shoulder is a billable credential.
    await cubit.load();
    await pump(t);
    await t.tap(
      find.byKey(
        AppKeys.voiceSettingsProviderTile(SttProviderType.volcengine.name),
      ),
    );
    await t.pumpAndSettle();

    TextField fieldFor(String name) => t.widget<TextField>(
      find.byKey(AppKeys.voiceSettingsCredentialField(name)),
    );
    expect(fieldFor('volcAccessToken').obscureText, isTrue);
    expect(fieldFor('volcAppId').obscureText, isFalse);
  });

  testWidgets('shows the cloud privacy note only for cloud services', (t) async {
    await cubit.load();
    await pump(t);
    final note = find.textContaining('not through the encrypted pairing');
    expect(note, findsNothing, reason: 'on-device recognition sends nothing');

    await t.tap(
      find.byKey(
        AppKeys.voiceSettingsProviderTile(SttProviderType.aliyun.name),
      ),
    );
    await t.pumpAndSettle();
    expect(note, findsOneWidget);
  });

  testWidgets('the language row defaults to following the system', (t) async {
    await cubit.load();
    await pump(t);
    expect(find.text('System default'), findsOneWidget);
  });

  testWidgets('picking a language persists it', (t) async {
    await cubit.load();
    await pump(t);
    await t.tap(find.byKey(AppKeys.voiceSettingsLanguageTile));
    await t.pumpAndSettle();
    await t.tap(find.text('简体中文').last);
    await t.pumpAndSettle();

    expect(cubit.state.localeId, isNotEmpty);
    expect(repository.lastSavedPrefs!.localeId, cubit.state.localeId);
  });

  testWidgets('a passing connection test reports the latency', (t) async {
    await cubit.load();
    await pump(t);
    await t.tap(
      find.byKey(
        AppKeys.voiceSettingsProviderTile(SttProviderType.volcengine.name),
      ),
    );
    await t.pumpAndSettle();

    provider.testConnectionMillis = 137;
    await t.tap(find.byKey(AppKeys.voiceSettingsTestButton));
    await t.pumpAndSettle();

    expect(find.text('Connected in 137 ms'), findsOneWidget);
  });

  testWidgets('a failing connection test says so', (t) async {
    await cubit.load();
    await pump(t);
    await t.tap(
      find.byKey(
        AppKeys.voiceSettingsProviderTile(SttProviderType.volcengine.name),
      ),
    );
    await t.pumpAndSettle();

    provider.testConnectionError = const SttException('bad key');
    await t.tap(find.byKey(AppKeys.voiceSettingsTestButton));
    await t.pumpAndSettle();

    expect(find.text('Connection failed'), findsOneWidget);
  });
}
```

- [ ] **Step 3: 跑测试确认失败**

```bash
cd client && flutter test test/pages/pairing/voice_settings_page_test.dart
```

预期：`Target of URI doesn't exist: 'package:teampilot/pages/pairing/voice/voice_settings_page.dart'`。

- [ ] **Step 4: 写 `voice_settings_page.dart`**

要求：

- `static Route<void> route(VoiceInputCubit cubit) => MaterialPageRoute(builder: (_) => BlocProvider.value(value: cubit, child: const VoiceSettingsPage()));` —— 与 `MobileToolbarCustomizePage.route()`（`mobile_toolbar_customize_page.dart:21`）同一写法，调用方不会忘记跨路由重新提供 cubit。
- `Scaffold(key: AppKeys.voiceSettingsPage, appBar: AppBar(title: Text(l10n.voiceInputSettings)), body: …)`。
- `BlocBuilder<VoiceInputCubit, VoiceInputState>`，`buildWhen: (a, b) => a.provider != b.provider || a.localeId != b.localeId || a.credentials != b.credentials`（`VoiceCredentials` 有值相等，Task 7 已实现）。`status` 变化不该重画设置页。
- 自上而下：`voiceInputProvider` 分区标题 + 三个 `RadioListTile<SttProviderType>`（`key: AppKeys.voiceSettingsProviderTile(type.name)`，`onChanged` 调 `cubit.setProvider`）→ 语言行 `ListTile(key: AppKeys.voiceSettingsLanguageTile, title: Text(l10n.voiceInputLanguage), subtitle: Text(当前语言名或 l10n.voiceInputLanguageDefault), onTap: 推语言选择)` → 云端时的 `voiceInputCredentials` 分区与字段 → 云端时的测试按钮 → 云端时的隐私说明。
- 语言选择用 `showModalBottomSheet`（与 `mobile_settings_sheet.dart:15`、`pairing_manual_entry_sheet.dart:15` 同一惯例），列 `sttLocalesFor(state.provider)`，首项为 `l10n.voiceInputLanguageDefault`（值 `''`），选中回 `cubit.setLocaleId`。
- 凭据字段：私有 `_CredentialField extends StatefulWidget`，持有自己的 `TextEditingController`（`initState` 用 `cubit.state.credentials.field(f)` 播种）与 `Debouncer(tag: 'voice-cred-${f.name}', duration: const Duration(milliseconds: 500))`（`lib/utils/debounce/debounces.dart`）。`onChanged` 走 debounce、`onSubmitted` 立即落盘，两者都调 `cubit.setCredential(f, value)`。照 `session_config_section.dart` 的表单惯例。`key: AppKeys.voiceSettingsCredentialField(f.name)`。`obscureText` 仅对 `volcAccessToken` 与 `aliyunAccessKeySecret` 为真。
- 测试按钮：`ListTile(key: AppKeys.voiceSettingsTestButton, ...)`，`onTap` 里 `try { final ms = await cubit.testConnection(); messenger.showSnackBar(SnackBar(content: Text(l10n.voiceInputTestPassed(ms)))); } on Object { messenger.showSnackBar(SnackBar(content: Text(l10n.voiceInputTestFailed))); }`。**`await` 之前先取 `ScaffoldMessenger.of(context)`**，异步之后再用 `context` 会触发 `use_build_context_synchronously` lint 且页面可能已 pop。测试期间禁用按钮（本地 `bool _testing` + `setState`，这是纯本地 UI 状态，不违反 flutter_bloc 规则）。
- 隐私说明：`Padding` 包 `Text(l10n.voiceInputCloudPrivacyNote, style: 小号 onSurfaceVariant)`，仅 `state.provider != SttProviderType.system` 时渲染。
- 文件不得超过 ~350 行；超了把凭据分区抽到 `voice_credentials_section.dart`。

- [ ] **Step 5: 跑测试确认通过**

```bash
cd client && flutter test test/pages/pairing/voice_settings_page_test.dart
```

预期：`All tests passed!`，11 个测试。

- [ ] **Step 6: 接两个入口**

`client/lib/pages/pairing/mobile_settings_sheet.dart`：在 `TpCard.outlined(child: const AppearanceControls())` 之后加一张卡，内含一行

```dart
ListTile(
  key: AppKeys.mobileSettingsVoiceRow,
  leading: const Icon(Icons.mic_none),
  title: Text(l10n.voiceInputSettings),
  trailing: const Icon(Icons.chevron_right),
  onTap: () => Navigator.of(context).push(
    VoiceSettingsPage.route(context.read<VoiceInputCubit>()),
  ),
),
```

`VoiceInputCubit` 已由 Task 9 提供在 `PairingMobileShell` 层，所以这个挂在 `PairedHostsPage` 上的 sheet 里 `context.read<VoiceInputCubit>()` 直接可用 —— 这正是当初把它放在 shell 而不是镜像页的原因。

`mobile_composer_panel.dart` 的未配置 tap 与长按：
- `idle` 且 `!state.configured` 时，`onTap` 改为 `Navigator.of(context).push(VoiceSettingsPage.route(context.read<VoiceInputCubit>()))`，并把 Task 9 留下的那句说明注释换成真实行为的注释。
- 麦克风按钮外层包 `GestureDetector(onLongPress: () => Navigator.of(context).push(VoiceSettingsPage.route(...)))`。长按是空闲手势（交互选的是点按切换），给设置页一条就近入口。

- [ ] **Step 7: 补两条入口测试**

在 `voice_settings_page_test.dart` 末尾加：

```dart
  testWidgets('route() pushes the page with the cubit still in scope', (
    t,
  ) async {
    // The route helper exists so a caller cannot forget to re-provide the cubit
    // across the route boundary; this fails with ProviderNotFoundException if
    // the BlocProvider.value inside route() is ever dropped.
    await cubit.load();
    await t.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider.value(
          value: cubit,
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).push(VoiceSettingsPage.route(cubit)),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byKey(AppKeys.voiceSettingsPage), findsOneWidget);
  });
```

麦克风的两条手势在 `composer_mic_button_test.dart` 里加：

```dart
  testWidgets('long-pressing the mic opens voice settings', (t) async {
    await voice.load();
    await pump(t);
    await t.longPress(find.byKey(AppKeys.mobileComposerMicButton));
    await t.pumpAndSettle();
    expect(find.byKey(AppKeys.voiceSettingsPage), findsOneWidget);
  });

  testWidgets('tapping an unconfigured mic opens voice settings', (t) async {
    // The tap's only useful outcome is configuration, so go there instead of
    // reporting a failure the user cannot act on from here.
    await voiceRepository.savePrefs(
      const VoiceInputPrefs(provider: SttProviderType.aliyun, localeId: ''),
    );
    await voice.load();
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerMicButton));
    await t.pumpAndSettle();
    expect(find.byKey(AppKeys.voiceSettingsPage), findsOneWidget);
    expect(provider.startCalls, 0);
  });
```

- [ ] **Step 8: 全量测试与 analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
```

预期：analyze `No issues found!`（或仅 A 期遗留的 `onReorder` deprecated info）。测试预期全绿，**除了两个既存失败**：`test/pages/command_palette_overlay_test.dart` 与 `test/services/pty_launch_environment_test.dart`。这两个在本分支基线上就失败，不准碰。若有第三个文件失败，先在基线上确认它是否本来就失败，再决定。

- [ ] **Step 9: 提交**

```bash
cd /Users/yitouxiaomaolv/git/cmux && git add \
  client/lib/pages/pairing/voice/voice_settings_page.dart \
  client/lib/pages/pairing/mobile_settings_sheet.dart \
  client/lib/pages/pairing/mobile_toolbar/mobile_composer_panel.dart \
  client/lib/utils/ui/app_keys.dart \
  client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations.dart \
  client/lib/l10n/app_localizations_en.dart \
  client/lib/l10n/app_localizations_zh.dart \
  client/lib/theme/warmup_glyphs.g.dart \
  client/test/pages/pairing/voice_settings_page_test.dart \
  client/test/pages/pairing/composer_mic_button_test.dart \
  client/test/cubits/voice_input_cubit_test.dart && \
git commit -m "feat(voice): add the voice settings page

Two entry points: a row in the phone's settings sheet, and a long press on
the mic — the gesture is spare because dictation is tap-to-toggle. Tapping
an unconfigured mic goes here too, since configuration is the tap's only
useful outcome.

The connection test replaces the reference implementation's speed test:
whether a key pair works is the question a user actually has on day one,
and a latency number alone does not answer it."
```

若实现过程中另有文件需要改动，一并显式列进 `git add`，但仍**不准**用 `git add -A`。

---

## 收尾

全部任务完成后：

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
```

然后交由 `superpowers:finishing-a-development-branch` 处理分支。

真机验证清单（自动化测试覆盖不到，但每条都能一眼看出坏没坏）：

1. iOS 首次点麦克风 → 出现两次系统弹窗（麦克风、语音识别）；拒绝后再点 → snackbar 提示去系统设置。
2. Android 首次点麦克风 → 出现录音权限弹窗；`initialize()` 返回 true（若恒 false，检查 `<queries>` 是否真的进了合并后的清单）。
3. 说一句话 → 文本出现在输入框，光标在末尾；再说一句 → 接在后面而不是覆盖。
4. 切到豆包、填错 token → 测试连接报失败；填对 → 报毫秒数。
5. 开着录音把 Composer 关掉 → 状态栏麦克风指示消失（iOS 橙点 / Android 麦克风图标）。
6. 开着录音退出镜像页 → 同上。
7. 开着录音等 60 秒 → 自动停止，已识别文本保留。
