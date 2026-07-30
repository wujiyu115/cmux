import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_image_clipboard.dart';
import 'package:teampilot/services/terminal/terminal_clipboard_image_paste.dart';
import 'package:teampilot/services/terminal/terminal_path_drop_behavior.dart';
import 'package:teampilot/services/workspace_dnd/path_reference_formatter.dart';
import 'package:teampilot/services/workspace_dnd/runtime_target.dart';
import 'package:teampilot/services/workspace_dnd/terminal_text_sink.dart';

/// Clipboard reader with canned answers; records how often each side is read so
/// the file-path-before-bytes priority can be asserted.
class _FakeReader implements ComposeImageClipboardReader {
  _FakeReader({this.paths = const [], this.bytes});

  final List<String> paths;
  final ComposeImageClipboardPayload? bytes;
  int fileCalls = 0;
  int byteCalls = 0;

  @override
  Future<List<String>> readImageFilePaths() async {
    fileCalls++;
    return paths;
  }

  @override
  Future<ComposeImageClipboardPayload?> readImageBytes() async {
    byteCalls++;
    return bytes;
  }
}

/// Captures whatever the drop ingestor injects, standing in for a live PTY.
class _FakeSink implements TerminalTextSink {
  final appended = <String>[];
  final pasted = <String>[];

  @override
  void appendText(String text) => appended.add(text);

  @override
  Future<void> pasteWithoutSubmit(String text) async => pasted.add(text);
}

void main() {
  const rawBehavior = TerminalPathDropBehavior(
    mode: TerminalPathDropMode.rawAppend,
    quoting: PathQuoting.posixQuoteIfNeeded,
  );

  final onWindows = !kIsWeb && Platform.isWindows;
  // A path spelled in the host namespace so a matching host target passes it
  // through unchanged (no cross-namespace projection to reason about).
  final hostImagePath = onWindows ? r'C:\shots\a.png' : '/shots/a.png';
  final hostTarget = onWindows
      ? const RuntimeTarget.localWindows()
      : const RuntimeTarget.localPosix();

  ComposeImageClipboardPayload pngPayload() =>
      const ComposeImageClipboardPayload(bytes: [1, 2, 3], extension: 'png');

  test('clipboard image file path is injected into the input line', () async {
    final sink = _FakeSink();
    final paste = TerminalClipboardImagePaste(
      reader: _FakeReader(paths: [hostImagePath]),
    );

    final ok = await paste.tryPasteImage(
      sink: sink,
      target: hostTarget,
      behavior: rawBehavior,
    );

    expect(ok, isTrue);
    expect(sink.appended.single, contains('a.png'));
    expect(sink.pasted, isEmpty);
  });

  test('clipboard image bytes are persisted to a scratch file and injected',
      () async {
    final tmp = await Directory.systemTemp.createTemp('tp-paste-test');
    addTearDown(() => tmp.delete(recursive: true));
    final sink = _FakeSink();
    final paste = TerminalClipboardImagePaste(
      reader: _FakeReader(bytes: pngPayload()),
      scratchDir: tmp,
      now: () => DateTime.fromMicrosecondsSinceEpoch(42),
    );

    final ok = await paste.tryPasteImage(
      sink: sink,
      target: hostTarget,
      behavior: rawBehavior,
    );

    expect(ok, isTrue);
    expect(sink.appended.single, contains('paste-42.png'));
    expect(File('${tmp.path}/paste-42.png').existsSync(), isTrue);
  });

  test('pasted image bytes project into a WSL /mnt path for a WSL target',
      () async {
    final tmp = await Directory.systemTemp.createTemp('tp-paste-test');
    addTearDown(() => tmp.delete(recursive: true));
    final sink = _FakeSink();
    final paste = TerminalClipboardImagePaste(
      reader: _FakeReader(bytes: pngPayload()),
      scratchDir: tmp,
      now: () => DateTime.fromMicrosecondsSinceEpoch(42),
    );

    final ok = await paste.tryPasteImage(
      sink: sink,
      target: const RuntimeTarget.wsl(),
      behavior: rawBehavior,
    );

    expect(ok, isTrue);
    expect(sink.appended.single, contains('/mnt/'));
    expect(sink.appended.single, contains('paste-42.png'));
  }, skip: onWindows ? false : 'Windows host namespace only');

  test('SSH target rejects the local scratch file so text fallback runs',
      () async {
    final tmp = await Directory.systemTemp.createTemp('tp-paste-test');
    addTearDown(() => tmp.delete(recursive: true));
    final sink = _FakeSink();
    final paste = TerminalClipboardImagePaste(
      reader: _FakeReader(bytes: pngPayload()),
      scratchDir: tmp,
      now: () => DateTime.fromMicrosecondsSinceEpoch(42),
    );

    final ok = await paste.tryPasteImage(
      sink: sink,
      target: const RuntimeTarget.ssh(),
      behavior: rawBehavior,
    );

    expect(ok, isFalse);
    expect(sink.appended, isEmpty);
    expect(sink.pasted, isEmpty);
  });

  test('empty clipboard delivers nothing and reports no image', () async {
    final sink = _FakeSink();
    final reader = _FakeReader();
    final paste = TerminalClipboardImagePaste(reader: reader);

    final ok = await paste.tryPasteImage(
      sink: sink,
      target: hostTarget,
      behavior: rawBehavior,
    );

    expect(ok, isFalse);
    expect(sink.appended, isEmpty);
    expect(reader.fileCalls, 1);
    expect(reader.byteCalls, 1);
  });

  test('image file paths take priority over image bytes', () async {
    final sink = _FakeSink();
    final reader = _FakeReader(paths: [hostImagePath], bytes: pngPayload());
    final paste = TerminalClipboardImagePaste(reader: reader);

    final ok = await paste.tryPasteImage(
      sink: sink,
      target: hostTarget,
      behavior: rawBehavior,
    );

    expect(ok, isTrue);
    expect(reader.byteCalls, 0, reason: 'file paths short-circuit byte read');
  });
}
