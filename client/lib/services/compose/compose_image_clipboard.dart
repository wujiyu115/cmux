import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pasteboard/pasteboard.dart';

import 'compose_image_attachment.dart';

/// Clipboard image payload for landing compose import.
class ComposeImageClipboardPayload {
  const ComposeImageClipboardPayload({
    required this.bytes,
    required this.extension,
  });

  final List<int> bytes;
  final String extension;
}

/// Reads image data or image file paths from the system clipboard.
abstract interface class ComposeImageClipboardReader {
  Future<ComposeImageClipboardPayload?> readImageBytes();

  Future<List<String>> readImageFilePaths();
}

/// Desktop/mobile clipboard reader backed by [Pasteboard].
class PasteboardComposeImageClipboardReader
    implements ComposeImageClipboardReader {
  const PasteboardComposeImageClipboardReader();

  static bool get supported =>
      !kIsWeb &&
      (Platform.isLinux ||
          Platform.isMacOS ||
          Platform.isWindows ||
          Platform.isAndroid);

  @override
  Future<ComposeImageClipboardPayload?> readImageBytes() async {
    if (!supported) return null;
    final bytes = await Pasteboard.image;
    if (bytes == null || bytes.isEmpty) return null;
    // Windows' Pasteboard.image hands back a BMP file (CF_DIB → CreateBMPFile);
    // saving that under a `.png` name makes every downstream image reader
    // reject it, so re-encode once here — see [ensurePngBytes].
    return ComposeImageClipboardPayload(
      bytes: await ensurePngBytes(Uint8List.fromList(bytes)),
      extension: 'png',
    );
  }

  @override
  Future<List<String>> readImageFilePaths() async {
    if (!supported) return const [];
    final paths = await Pasteboard.files();
    final text = await Pasteboard.text;
    return parseClipboardImageFilePaths(filePaths: paths, clipboardText: text);
  }
}

/// Resolves image file paths from pasteboard file URIs and GNOME clipboard text.
List<String> parseClipboardImageFilePaths({
  required List<String> filePaths,
  required String? clipboardText,
}) {
  final resolved = <String>[];
  final seen = <String>{};

  void addPath(String raw) {
    final path = _normalizeClipboardPath(raw);
    if (path.isEmpty || !isComposeImagePath(path)) return;
    if (seen.add(path)) resolved.add(path);
  }

  for (final path in filePaths) {
    addPath(path);
  }

  final text = clipboardText?.trim();
  if (text == null || text.isEmpty) return resolved;

  final lines = text.split('\n');
  final start =
      lines.isNotEmpty && (lines.first == 'copy' || lines.first == 'cut')
      ? 1
      : 0;
  for (var i = start; i < lines.length; i++) {
    addPath(lines[i]);
  }

  return resolved;
}

String _normalizeClipboardPath(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.startsWith('file://')) {
    try {
      final uri = Uri.parse(trimmed);
      final looksLikeWindowsFileUri = RegExp(
        r'^/[A-Za-z]:/',
      ).hasMatch(uri.path);
      return uri.toFilePath(
        windows: Platform.isWindows && looksLikeWindowsFileUri,
      );
    } on Object {
      return trimmed.substring('file://'.length);
    }
  }
  return trimmed;
}

/// Returns [bytes] as genuine PNG, re-encoding when the clipboard held
/// something else.
///
/// The payload always lands in a file named `.png` ([ComposeImageClipboardPayload]
/// carries no format of its own), so the bytes must actually *be* PNG or every
/// reader — agent vision, image previews — chokes and the user converts by
/// hand. On Windows the screenshot path is BMP end to end; macOS/Linux/Android
/// already deliver PNG and take the fast pass-through. Bytes the engine cannot
/// decode are returned unchanged rather than dropped.
Future<Uint8List> ensurePngBytes(Uint8List bytes) async {
  if (isPngBytes(bytes)) return bytes;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      try {
        final encoded = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (encoded != null) return encoded.buffer.asUint8List();
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } on Object {
    // Undecodable: keep the original bytes instead of losing the paste.
  }
  return bytes;
}

/// PNG signature: `0x89 P N G 0x0d 0x0a 0x1a 0x0a`.
bool isPngBytes(Uint8List bytes) =>
    bytes.length >= 8 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4e &&
    bytes[3] == 0x47 &&
    bytes[4] == 0x0d &&
    bytes[5] == 0x0a &&
    bytes[6] == 0x1a &&
    bytes[7] == 0x0a;
