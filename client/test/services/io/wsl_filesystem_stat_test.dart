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

  group('WslFilesystem.statAndReadBytes', () {
    test('returns stat and content from a single spawn', () async {
      List<String>? capturedArgs;
      const text = 'hello 中文 🚀';
      final b64 = base64.encode(utf8.encode(text));
      final fs = WslFilesystem(
        processRunner: (executable, arguments,
            {stdoutEncoding, stderrEncoding}) async {
          expect(executable, 'wsl.exe');
          capturedArgs = arguments;
          return ProcessResult(0, 0, 'regular file|42|1700000000\n$b64', '');
        },
      );

      final result = await fs.statAndReadBytes(
        '/tmp/f.txt',
        maxBytes: 100,
      );

      expect(capturedArgs!.sublist(0, 4), [
        '--exec',
        'sh',
        '-c',
        predicate<String>(
          (script) =>
              script.contains('stat -c "\$2" -- "\$1"') &&
              script.contains('head -c "\$3" -- "\$1" | base64 -w0'),
        ),
      ]);
      expect(capturedArgs!.sublist(4), [
        'sh',
        '/tmp/f.txt',
        '%F|%s|%Y',
        '100',
      ]);
      expect(result!.stat.kind, FsEntityKind.file);
      expect(result.stat.size, 42);
      expect(utf8.decode(result.bytes!), text);
    });

    test('omits the head cap when maxBytes is null', () async {
      List<String>? capturedArgs;
      final fs = WslFilesystem(
        processRunner: (executable, arguments,
            {stdoutEncoding, stderrEncoding}) async {
          capturedArgs = arguments;
          return ProcessResult(0, 0, 'regular file|1|1700000000\naGk=', '');
        },
      );

      await fs.statAndReadBytes('/tmp/f.txt');

      final script = capturedArgs![3];
      expect(script, contains('base64 -w0 -- "\$1"'));
      expect(script, isNot(contains('head')));
      expect(capturedArgs!.length, 7); // no maxBytes positional
    });

    test('empty file yields empty bytes, not a failed read', () async {
      final fs = WslFilesystem(
        processRunner: (_, __, {stdoutEncoding, stderrEncoding}) async =>
            ProcessResult(0, 0, 'regular empty file|0|1700000000\n', ''),
      );

      final result = await fs.statAndReadBytes('/tmp/empty.txt');

      expect(result!.stat.kind, FsEntityKind.file);
      expect(result.bytes, isEmpty);
    });

    test('missing file returns null', () async {
      final fs = WslFilesystem(
        processRunner: (_, __, {stdoutEncoding, stderrEncoding}) async =>
            ProcessResult(0, 1, '', 'No such file'),
      );

      expect(
        await fs.statAndReadBytes('/missing', maxBytes: 10),
        isNull,
      );
    });

    test('unreadable file returns stat with null bytes', () async {
      final fs = WslFilesystem(
        processRunner: (_, __, {stdoutEncoding, stderrEncoding}) async =>
            ProcessResult(0, 2, 'regular file|6|1700000000\n', 'denied'),
      );

      final result = await fs.statAndReadBytes('/tmp/noperm', maxBytes: 10);

      expect(result!.stat.kind, FsEntityKind.file);
      expect(result.bytes, isNull);
    });
  });

  group('WslFilesystem.existsMany', () {
    test('checks every path in a single spawn', () async {
      List<String>? capturedArgs;
      final fs = WslFilesystem(
        processRunner: (executable, arguments,
            {stdoutEncoding, stderrEncoding}) async {
          expect(executable, 'wsl.exe');
          capturedArgs = arguments;
          return ProcessResult(0, 0, 'yny', '');
        },
      );

      final result = await fs.existsMany(['/a', '/b', '/c']);

      final script = capturedArgs![3];
      expect(script, contains('[ -e "\$f" ]'));
      expect(capturedArgs!.sublist(4), ['sh', '/a', '/b', '/c']);
      expect(result, {'/a': true, '/b': false, '/c': true});
    });

    test('empty input returns empty without spawning', () async {
      final fs = WslFilesystem(
        processRunner: (_, __, {stdoutEncoding, stderrEncoding}) async {
          fail('must not spawn for an empty path list');
        },
      );

      expect(await fs.existsMany(const []), isEmpty);
    });

    test('flag/output length mismatch throws', () async {
      final fs = WslFilesystem(
        processRunner: (_, __, {stdoutEncoding, stderrEncoding}) async =>
            ProcessResult(0, 0, 'y', ''),
      );

      await expectLater(
        fs.existsMany(['/a', '/b']),
        throwsStateError,
      );
    });
  });

  group('WslFilesystem.createTempDir', () {
    // Regression: a relative template made mktemp create the directory in
    // wsl.exe's process cwd and return a *relative* path, which the phone
    // then couldn't read back (e.g. `teampilot-upload-714Vzu/…`).
    test('passes an absolute /tmp template and returns mktemp output', () async {
      List<String>? capturedArgs;
      final fs = WslFilesystem(
        processRunner: (executable, arguments,
            {stdoutEncoding, stderrEncoding}) async {
          capturedArgs = arguments;
          return ProcessResult(0, 0, '/tmp/teampilot-upload-714Vzu\n', '');
        },
      );

      final dir = await fs.createTempDir(prefix: 'teampilot-upload-');

      expect(capturedArgs, [
        '--exec',
        'mktemp',
        '-d',
        '--',
        '/tmp/teampilot-upload-XXXXXX',
      ]);
      expect(dir, '/tmp/teampilot-upload-714Vzu');
    });

    test('honors an explicit parent', () async {
      List<String>? capturedArgs;
      final fs = WslFilesystem(
        processRunner: (executable, arguments,
            {stdoutEncoding, stderrEncoding}) async {
          capturedArgs = arguments;
          return ProcessResult(0, 0, '/var/cache/tmp-x1\n', '');
        },
      );

      await fs.createTempDir(parent: '/var/cache');

      expect(capturedArgs?.last, '/var/cache/tmpXXXXXX');
    });

    test('throws when mktemp fails', () async {
      final fs = WslFilesystem(
        processRunner: (_, __, {stdoutEncoding, stderrEncoding}) async =>
            ProcessResult(0, 1, '', 'No such file or directory'),
      );

      await expectLater(
        fs.createTempDir(),
        throwsStateError,
      );
    });
  });

  group('WslFilesystem.stdout decoding', () {
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
