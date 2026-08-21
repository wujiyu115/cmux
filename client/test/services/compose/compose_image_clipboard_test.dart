import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_image_clipboard.dart';

/// A minimal 1x1 24-bpp BMP file — the shape Windows' clipboard path produces
/// (pasteboard reads CF_DIB and writes it out with CreateBMPFile).
Uint8List _onePixelBmp() => Uint8List.fromList([
      0x42, 0x4d, // 'BM'
      0x3a, 0x00, 0x00, 0x00, // file size: 58
      0x00, 0x00, 0x00, 0x00, // reserved
      0x36, 0x00, 0x00, 0x00, // pixel data offset: 54
      // BITMAPINFOHEADER
      0x28, 0x00, 0x00, 0x00, // header size: 40
      0x01, 0x00, 0x00, 0x00, // width: 1
      0x01, 0x00, 0x00, 0x00, // height: 1
      0x01, 0x00, // planes
      0x18, 0x00, // 24 bpp
      0x00, 0x00, 0x00, 0x00, // BI_RGB
      0x04, 0x00, 0x00, 0x00, // image size: 4 (3 + row padding)
      0x13, 0x0b, 0x00, 0x00, // x pixels/meter
      0x13, 0x0b, 0x00, 0x00, // y pixels/meter
      0x00, 0x00, 0x00, 0x00, // colours used
      0x00, 0x00, 0x00, 0x00, // important colours
      // one BGR pixel + one padding byte
      0xff, 0x00, 0x00, 0x00,
    ]);

Future<Uint8List> _onePixelPng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 1, 1),
    ui.Paint()..color = const ui.Color(0xffff0000),
  );
  final image = await recorder.endRecording().toImage(1, 1);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseClipboardImageFilePaths', () {
    test('parses GNOME copied-files clipboard text', () {
      expect(
        parseClipboardImageFilePaths(
          filePaths: const [],
          clipboardText: 'copy\nfile:///home/user/Pictures/shot.png',
        ),
        ['/home/user/Pictures/shot.png'],
      );
    });

    test('ignores non-image paths from clipboard text', () {
      expect(
        parseClipboardImageFilePaths(
          filePaths: const [],
          clipboardText: 'copy\nfile:///home/user/readme.md',
        ),
        isEmpty,
      );
    });
  });

  group('ensurePngBytes', () {
    test('re-encodes Windows clipboard BMP into a real PNG', () async {
      final png = await ensurePngBytes(_onePixelBmp());
      expect(isPngBytes(png), isTrue);
      final codec = await ui.instantiateImageCodec(png);
      try {
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 1);
        expect(frame.image.height, 1);
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
    });

    test('passes PNG through untouched', () async {
      final png = await _onePixelPng();
      expect(identical(await ensurePngBytes(png), png), isTrue);
    });

    test('undecodable bytes come back unchanged, not dropped', () async {
      final garbage = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(identical(await ensurePngBytes(garbage), garbage), isTrue);
    });
  });
}
