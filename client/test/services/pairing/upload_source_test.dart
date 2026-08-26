import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/pairing/upload_source.dart';

Uint8List payload(int n) => Uint8List.fromList(List.generate(n, (i) => i & 0xff));

/// Pulls [source] dry in [chunk]-sized bites and returns what came back.
Future<List<Uint8List>> drain(UploadSource source, int chunk) async {
  final out = <Uint8List>[];
  while (true) {
    final bytes = await source.read(chunk);
    if (bytes.isEmpty) break;
    out.add(bytes);
  }
  return out;
}

void main() {
  group('MemoryUploadSource', () {
    test('reports the payload length', () {
      expect(MemoryUploadSource(payload(10)).length, 10);
      expect(MemoryUploadSource(Uint8List(0)).length, 0);
    });

    test('reads sequentially in maxBytes bites, short at the end', () async {
      final chunks = await drain(MemoryUploadSource(payload(10)), 4);
      expect(chunks.map((c) => c.length), [4, 4, 2]);
      expect(
        chunks.expand((c) => c).toList(),
        payload(10),
        reason: 'concatenating the chunks reproduces the payload',
      );
    });

    test('an empty source reads empty immediately', () async {
      expect(await MemoryUploadSource(Uint8List(0)).read(4), isEmpty);
    });

    test('keeps reading empty past EOF', () async {
      final source = MemoryUploadSource(payload(2));
      expect((await source.read(4)).length, 2);
      expect(await source.read(4), isEmpty);
      expect(await source.read(4), isEmpty);
    });

    test('close is harmless', () async {
      await expectLater(MemoryUploadSource(payload(1)).close(), completes);
    });
  });

  group('FileUploadSource', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('upload-source-test');
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    Future<File> write(int bytes) async {
      final file = File('${dir.path}${Platform.pathSeparator}clip.mp4');
      await file.writeAsBytes(payload(bytes));
      return file;
    }

    test('stats the length at open', () async {
      final file = await write(4096);
      final source = await FileUploadSource.open(file.path);
      addTearDown(source.close);
      expect(source.length, 4096);
    });

    test('reads the whole file sequentially in maxBytes bites', () async {
      final file = await write(10);
      final source = await FileUploadSource.open(file.path);
      addTearDown(source.close);

      final chunks = await drain(source, 4);

      expect(chunks.map((c) => c.length), [4, 4, 2]);
      expect(chunks.expand((c) => c).toList(), payload(10));
    });

    test('opens no handle until the first read', () async {
      // A pick rejected by the local size check must not leave a file handle
      // open — on iOS that is a real OS resource.
      final file = await write(8);
      final source = await FileUploadSource.open(file.path);
      await expectLater(source.close(), completes);
    });

    test('a file that shrank after open reads short of its declared length',
        () async {
      // The sender relies on this: a short read ends the loop with
      // `sent < total`, and the host's `received != declaredSize` check turns
      // that into `write_failed` rather than a truncated file on disk.
      final file = await write(10);
      final source = await FileUploadSource.open(file.path);
      addTearDown(source.close);
      expect(source.length, 10);

      await file.writeAsBytes(payload(3));
      final chunks = await drain(source, 4);

      expect(chunks.expand((c) => c).length, lessThan(source.length));
    });

    test('close twice is harmless', () async {
      final file = await write(4);
      final source = await FileUploadSource.open(file.path);
      await source.read(4);
      await source.close();
      await expectLater(source.close(), completes);
    });
  });
}
