import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/file_editor_theme.dart';

void main() {
  test('isImagePreviewPath allowlist', () {
    expect(isImagePreviewPath('/a/b.PNG'), isTrue);
    expect(isImagePreviewPath('/a/photo.jpeg'), isTrue);
    expect(isImagePreviewPath('/a/x.webp'), isTrue);
    expect(isImagePreviewPath('/a/x.gif'), isTrue);
    expect(isImagePreviewPath('/a/x.bmp'), isTrue);
    expect(isImagePreviewPath('/a/x.svg'), isFalse);
    expect(isImagePreviewPath('/a/x.txt'), isFalse);
    expect(isImagePreviewPath('/a/x.heic'), isFalse);
  });

  test('workbench openable is text, image, or unknown; svg stays text-only',
      () {
    expect(isWorkbenchOpenableFilePath('/a/x.png'), isTrue);
    expect(isWorkbenchOpenableFilePath('/a/x.dart'), isTrue);
    expect(isWorkbenchOpenableFilePath('/a/x.svg'), isTrue);
    // Unknown extensions are optimistic; content sniffing decides later.
    expect(isWorkbenchOpenableFilePath('/a/hall.sproto'), isTrue);
    expect(isWorkbenchOpenableFilePath('/a/abyss_war.td'), isTrue);
    expect(isWorkbenchOpenableFilePath('/a/Dockerfile.dev'), isTrue);
    expect(isEditorOpenableFilePath('/a/x.png'), isFalse);
    expect(isEditorOpenableFilePath('/a/x.svg'), isTrue);
    expect(isEditorOpenableFilePath('/a/hall.sproto'), isFalse);
    expect(isWorkbenchOpenableFilePath('/a/x.pdf'), isFalse);
    expect(isWorkbenchOpenableFilePath('/a/x.zip'), isFalse);
    expect(isWorkbenchOpenableFilePath('/a/archive.tar.gz'), isFalse);
  });

  test('isKnownBinaryFilePath blocklist', () {
    expect(isKnownBinaryFilePath('/a/app.exe'), isTrue);
    expect(isKnownBinaryFilePath('/a/lib.DLL'), isTrue);
    expect(isKnownBinaryFilePath('/a/photo.jpeg'), isFalse);
    expect(isKnownBinaryFilePath('/a/notes.txt'), isFalse);
    expect(isKnownBinaryFilePath('/a/hall.sproto'), isFalse);
    expect(isKnownBinaryFilePath('/a/Makefile'), isFalse);
  });

  test('bytesSeemBinary scans the leading bytes for NUL', () {
    expect(bytesSeemBinary(<int>[]), isFalse);
    expect(bytesSeemBinary('hello'.codeUnits), isFalse);
    expect(bytesSeemBinary('你好'.codeUnits), isFalse);
    // UTF-8 BOM is text.
    expect(bytesSeemBinary([0xEF, 0xBB, 0xBF, 0x68, 0x69]), isFalse);
    expect(bytesSeemBinary([0x89, 0x50, 0x4E, 0x00]), isTrue);
    // NUL past the sniff window does not flag the file.
    expect(
      bytesSeemBinary([...List<int>.filled(kEditorBinarySniffBytes, 0x61), 0]),
      isFalse,
    );
  });

  test('compound suffixes fall back to the inner extension', () {
    expect(isEditorOpenableFilePath('/d/config.yaml.template'), isTrue);
    expect(isEditorOpenableFilePath('/d/upload_config.yaml.template'), isTrue);
    expect(isEditorOpenableFilePath('/d/notes.txt.bak'), isTrue);
    expect(isEditorOpenableFilePath('/d/start.sh'), isTrue);
    expect(isEditorOpenableFilePath('/d/archive.tar.gz'), isFalse);
    expect(isEditorOpenableFilePath('/d/photo.jpg.orig'), isFalse);
    expect(isEditorOpenableFilePath('/d/Dockerfile.dev'), isFalse);
  });

  test('kEditorMaxImageBytes is 25 MiB', () {
    expect(kEditorMaxImageBytes, 25 * 1024 * 1024);
  });
}
