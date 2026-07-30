import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_alacritty/input/paste.dart' as alacritty_paste;

import '../compose/compose_image_clipboard.dart';
import '../workspace_dnd/path_namespace.dart';
import '../workspace_dnd/runtime_target.dart';
import '../workspace_dnd/terminal_drop_ingestor.dart';
import '../workspace_dnd/terminal_text_sink.dart';
import '../workspace_dnd/workspace_file_ref.dart';
import 'terminal_path_drop_behavior.dart';

/// Terminal paste that understands images, matching cmux: a copied screenshot
/// (raw image bytes on the clipboard, no text) is written to a scratch file and
/// its path is injected into the input line; a plain-text clipboard falls
/// through to the normal bracketed-paste. Image *file* paths already on the
/// clipboard (copied in a file manager) are injected directly.
///
/// Path injection reuses the drag-and-drop pipeline ([TerminalDropIngestor]),
/// so namespace projection (WSL `/mnt`), quoting and full-screen paste-mode all
/// match a dropped file. Remote (SSH) targets can't name a local scratch file,
/// so the drop pipeline rejects it and the text fallback runs instead.
class TerminalClipboardImagePaste {
  TerminalClipboardImagePaste({
    ComposeImageClipboardReader reader =
        const PasteboardComposeImageClipboardReader(),
    Directory? scratchDir,
    DateTime Function() now = DateTime.now,
  }) : _reader = reader,
       _scratchDir = scratchDir,
       _now = now;

  final ComposeImageClipboardReader _reader;
  final Directory? _scratchDir;
  final DateTime Function() _now;

  /// Full paste: try an image path first, otherwise paste clipboard text.
  Future<void> paste({
    required TerminalEngine engine,
    required TerminalController controller,
    required TerminalTextSink sink,
    required RuntimeTarget target,
    required TerminalPathDropBehavior behavior,
  }) async {
    final pastedImage = await tryPasteImage(
      sink: sink,
      target: target,
      behavior: behavior,
    );
    if (pastedImage) return;

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    controller.onTerminalInputStart();
    engine.write(
      alacritty_paste.pasteBytes(text, modeFlags: engine.grid.modeFlags),
    );
    controller.clearSelection();
  }

  /// Injects a clipboard image as a file path. Returns true when something was
  /// delivered; false when the clipboard held no pasteable image (or the target
  /// couldn't name it locally), so the caller should fall back to text.
  Future<bool> tryPasteImage({
    required TerminalTextSink sink,
    required RuntimeTarget target,
    required TerminalPathDropBehavior behavior,
  }) async {
    final filePaths = await _reader.readImageFilePaths();
    if (filePaths.isNotEmpty) {
      return _inject(filePaths, sink: sink, target: target, behavior: behavior);
    }
    final payload = await _reader.readImageBytes();
    if (payload == null) return false;
    final saved = await _persist(payload);
    if (saved == null) return false;
    return _inject([saved], sink: sink, target: target, behavior: behavior);
  }

  Future<String?> _persist(ComposeImageClipboardPayload payload) async {
    try {
      final dir =
          _scratchDir ??
          Directory('${Directory.systemTemp.path}/teampilot-paste');
      await dir.create(recursive: true);
      final stamp = _now().microsecondsSinceEpoch;
      final file = File('${dir.path}/paste-$stamp.${payload.extension}');
      await file.writeAsBytes(payload.bytes, flush: true);
      return file.path;
    } on Object {
      return null;
    }
  }

  Future<bool> _inject(
    List<String> localPaths, {
    required TerminalTextSink sink,
    required RuntimeTarget target,
    required TerminalPathDropBehavior behavior,
  }) async {
    // The scratch/clipboard files live on the host machine; spell them in the
    // host's namespace so the drop pipeline can project into the target.
    final namespace = (!kIsWeb && Platform.isWindows)
        ? const PathNamespace.localWindows()
        : const PathNamespace.localPosix();
    final refs = [
      for (final path in localPaths)
        WorkspaceFileRef(
          nativePath: path,
          namespace: namespace,
          isDirectory: false,
        ),
    ];
    final ingestor = TerminalDropIngestor(
      sink: sink,
      target: target,
      behavior: behavior,
    );
    final outcome = await ingestor.consume(
      WorkspaceDragPayload(kind: DragPayloadKind.workspaceFile, refs: refs),
    );
    return outcome.anyDelivered;
  }
}
