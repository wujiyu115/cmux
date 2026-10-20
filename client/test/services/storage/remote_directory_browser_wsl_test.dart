import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/wsl_filesystem.dart';
import 'package:teampilot/services/storage/remote_directory_browser.dart';

/// End-to-end unit coverage of the directory-picker link for WSL targets:
/// `RemoteDirectoryBrowser(WslFilesystem)` is exactly what
/// `FuzzyDirectoryPickerDialog` / `RemoteDirectoryBrowserDialog` construct for
/// `wsl:*` targets (via `WorkspaceDirectoryPicker.filesystemFor`). Here the
/// `wsl.exe` process boundary is faked with canned `find` / `stat` output, so
/// the whole chain runs for real: windows side never touches the paths, the
/// distro reports POSIX basenames, and the browser must navigate purely with
/// the WSL filesystem's POSIX path context.
void main() {
  group('RemoteDirectoryBrowser over WslFilesystem', () {
    WslFilesystem wslFs({
      required Map<String, String> statOutput,
      required Map<String, String> findOutput,
      String? resolvedHome,
    }) {
      return WslFilesystem(
        processRunner: (executable, arguments,
            {stdoutEncoding, stderrEncoding}) async {
          expect(executable, 'wsl.exe');
          final script = arguments.whereType<String>().join(' ');
          // resolveSymlink: readlink -f -- <path>
          if (script.contains('readlink')) {
            if (resolvedHome == null) {
              return ProcessResult(0, 1, '', 'not a symlink');
            }
            return ProcessResult(0, 0, resolvedHome, '');
          }
          // stat: "%F|%s|%Y" per directory
          if (script.contains('stat')) {
            final target = arguments.last;
            final out = statOutput[target];
            if (out == null) return ProcessResult(0, 1, '', 'No such file');
            return ProcessResult(0, 0, '$out\n', '');
          }
          // listDir: find -L <path> -mindepth 1 -maxdepth 1 -printf "%f\t%y\n"
          final quoted =
              RegExp(r'find -L (\S+) -mindepth 1').firstMatch(script);
          if (quoted != null) {
            final raw = quoted.group(1)!;
            // shellSingleQuote wraps in single quotes.
            final path = raw.startsWith("'") ? raw.substring(1, raw.length - 1) : raw;
            final out = findOutput[path] ?? '';
            return ProcessResult(0, 0, out, '');
          }
          return ProcessResult(0, 1, '', 'unexpected call');
        },
      );
    }

    test('lists distro home with POSIX paths and basenames', () async {
      final fs = wslFs(
        statOutput: {'/home/ejoy': 'directory|4096|1700000000'},
        findOutput: {
          '/home/ejoy': 'projects\td\n'
              'Documents\td\n'
              'notes.md\tf\n'
              '.hidden\td\n'
              'linked-dir\td\n',
        },
      );
      final browser = RemoteDirectoryBrowser(fs);

      final listing = await browser.list('/home/ejoy');
      // Files filtered, hidden filtered, symlinks-to-dirs kept, sorted.
      expect(listing.path, '/home/ejoy');
      expect(listing.parent, '/home');
      expect(listing.directories, ['Documents', 'linked-dir', 'projects']);
    });

    test('child joins POSIX-style even though the host is Windows', () {
      final fs = wslFs(statOutput: const {}, findOutput: const {});
      final browser = RemoteDirectoryBrowser(fs);
      expect(browser.child('/home/ejoy', 'projects'), '/home/ejoy/projects');
    });

    test('parent is null at the distro filesystem root', () async {
      final fs = wslFs(
        statOutput: {'/': 'directory|4096|1700000000'},
        findOutput: {'/': 'home\td\n'},
      );
      final browser = RemoteDirectoryBrowser(fs);

      final listing = await browser.list('/');
      expect(listing.parent, isNull);
      expect(listing.directories, ['home']);
    });

    test('resolveInitial expands ~ against the distro home', () async {
      final fs = wslFs(
        statOutput: const {},
        findOutput: const {},
        resolvedHome: '/home/ejoy',
      );
      final browser = RemoteDirectoryBrowser(fs);

      expect(await browser.resolveInitial('~'), '/home/ejoy');
      expect(
        await browser.resolveInitial('~/projects/cmux'),
        '/home/ejoy/projects/cmux',
      );
    });
  });
}
