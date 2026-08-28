import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/wsl_filesystem.dart';

void main() {
  group('WslFilesystem.readString', () {
    test('decodes UTF-8 content regardless of Windows codepage', () async {
      const text = '# 标题\n中文内容 🚀';
      final b64 = base64.encode(utf8.encode(text));
      final fs = WslFilesystem(
        processRunner: (executable, arguments,
            {stdoutEncoding, stderrEncoding}) async {
          expect(executable, 'wsl.exe');
          // readBytes issues a base64 pipeline via `sh -lc`.
          expect(arguments, contains('sh'));
          return ProcessResult(0, 0, b64, '');
        },
      );
      expect(await fs.readString('/home/ejoy/README.md'), text);
    });
  });

  group('WslFilesystem.stat', () {
    test('parses size and mtime from stat -c output', () async {
      List<String>? capturedArgs;
      final fs = WslFilesystem(
        processRunner: (executable, arguments,
            {stdoutEncoding, stderrEncoding}) async {
          expect(executable, 'wsl.exe');
          capturedArgs = arguments;
          return ProcessResult(
            0,
            0,
            'regular file|42|1700000000\n',
            '',
          );
        },
      );

      final stat = await fs.stat('/tmp/partial.bin');

      expect(capturedArgs, [
        '--exec',
        'stat',
        '-c',
        '%F|%s|%Y',
        '--',
        '/tmp/partial.bin',
      ]);
      expect(stat.kind, FsEntityKind.file);
      expect(stat.size, 42);
      expect(
        stat.mtime,
        DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
      );
    });

    test('returns notFound when stat fails', () async {
      final fs = WslFilesystem(
        processRunner: (_, __, {stdoutEncoding, stderrEncoding}) async =>
            ProcessResult(0, 1, '', 'No such file'),
      );
      final stat = await fs.stat('/missing');
      expect(stat.kind, FsEntityKind.notFound);
      expect(stat.size, isNull);
    });

    test('parses directory without requiring size for resume', () async {
      final fs = WslFilesystem(
        processRunner: (_, __, {stdoutEncoding, stderrEncoding}) async =>
            ProcessResult(0, 0, 'directory|4096|1700000001\n', ''),
      );
      final stat = await fs.stat('/tmp');
      expect(stat.kind, FsEntityKind.directory);
      expect(stat.size, 4096);
    });
  });

  group('WslFilesystem stdout decoding', () {
    // Regression: `Process.run`'s default systemEncoding is the Windows console
    // codepage (GBK on zh-CN). wsl.exe always emits UTF-8, so a Chinese
    // filename in `find -printf %f` output came back as mojibake and the file
    // tree showed garbage names.
    test('listDir decodes UTF-8 filenames, not console-codepage bytes',
        () async {
      const stdoutText = '导表契约.md\tf\n加功能指南.md\tf\n';
      Encoding? seenStdoutEncoding;
      final fs = WslFilesystem(
        processRunner: (executable, arguments,
            {stdoutEncoding, stderrEncoding}) async {
          expect(executable, 'wsl.exe');
          final encoding = stdoutEncoding ?? const SystemEncoding();
          seenStdoutEncoding = encoding;
          return ProcessResult(
            0,
            0,
            encoding.decode(const Utf8Codec().encode(stdoutText)),
            '',
          );
        },
      );

      final entries = await fs.listDir('/home/u/doc');

      // The runner must have been asked for UTF-8, and the decoded names must
      // survive the round-trip. Under the old default (GBK) the same bytes
      // decode to 鍔犲姛鑳芥寚鍗-style mojibake.
      expect(seenStdoutEncoding, isA<Utf8Codec>());
      expect(
        entries.map((e) => e.name),
        ['导表契约.md', '加功能指南.md'],
      );
      expect(entries.every((e) => !e.isDirectory), isTrue);
    });

    test('readSymlinkTarget decodes UTF-8 targets', () async {
      const stdoutText = '/home/u/共享文件/链接目标\n';
      final fs = WslFilesystem(
        processRunner: (executable, arguments,
            {stdoutEncoding, stderrEncoding}) async {
          final encoding = stdoutEncoding ?? const SystemEncoding();
          return ProcessResult(
            0,
            0,
            encoding.decode(const Utf8Codec().encode(stdoutText)),
            '',
          );
        },
      );

      expect(
        await fs.readSymlinkTarget('/home/u/link'),
        '/home/u/共享文件/链接目标',
      );
    });
  });
}
