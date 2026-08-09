import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/pairing/upload_destination.dart';

/// Minimal hand-written [Filesystem] fake. Only [pathContext] and [stat] are
/// exercised by [resolveUploadDestination]; everything else throws so an
/// accidental new dependency on the filesystem surfaces loudly rather than
/// silently returning a wrong answer. [occupied] is the set of absolute paths
/// that report as existing.
class _FakeFilesystem implements Filesystem {
  _FakeFilesystem({p.Context? pathContext, Set<String>? occupied})
    : pathContext = pathContext ?? p.Context(style: p.Style.posix),
      _occupied = occupied ?? <String>{};

  @override
  final p.Context pathContext;

  final Set<String> _occupied;

  @override
  Future<FsStat> stat(String path) async {
    return _occupied.contains(path)
        ? const FsStat(kind: FsEntityKind.file)
        : const FsStat(kind: FsEntityKind.notFound);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  group('resolveUploadDestination', () {
    test('returns an unused name unchanged', () async {
      final fs = _FakeFilesystem();
      final path = await resolveUploadDestination(
        filesystem: fs,
        directory: '/cwd',
        filename: 'photo.jpg',
      );
      expect(path, '/cwd/photo.jpg');
    });

    test('occupied name yields -1, and -1 occupied yields -2', () async {
      final fs = _FakeFilesystem(
        occupied: {'/cwd/photo.jpg', '/cwd/photo-1.jpg'},
      );
      final path = await resolveUploadDestination(
        filesystem: fs,
        directory: '/cwd',
        filename: 'photo.jpg',
      );
      expect(path, '/cwd/photo-2.jpg');
    });

    test('suffix lands before the extension, never after', () async {
      final fs = _FakeFilesystem(occupied: {'/cwd/photo.jpg'});
      final path = await resolveUploadDestination(
        filesystem: fs,
        directory: '/cwd',
        filename: 'photo.jpg',
      );
      expect(path, '/cwd/photo-1.jpg');
      expect(path, isNot(contains('photo.jpg-1')));
    });

    test('name with no extension', () async {
      final fs = _FakeFilesystem(occupied: {'/cwd/README'});
      final path = await resolveUploadDestination(
        filesystem: fs,
        directory: '/cwd',
        filename: 'README',
      );
      expect(path, '/cwd/README-1');
    });

    test('name with several dots keeps only the last as extension', () async {
      final fs = _FakeFilesystem(occupied: {'/cwd/a.b.png'});
      final path = await resolveUploadDestination(
        filesystem: fs,
        directory: '/cwd',
        filename: 'a.b.png',
      );
      expect(path, '/cwd/a.b-1.png');
    });

    test('name that is only an extension-looking string', () async {
      // basenameWithoutExtension('.png') == '.png', extension('.png') == ''.
      final fs = _FakeFilesystem(occupied: {'/cwd/.png'});
      final path = await resolveUploadDestination(
        filesystem: fs,
        directory: '/cwd',
        filename: '.png',
      );
      expect(path, '/cwd/.png-1');
    });

    test('throws StateError once the 100-attempt cap is hit', () async {
      final occupied = <String>{'/cwd/photo.jpg'};
      for (var i = 1; i < 100; i++) {
        occupied.add('/cwd/photo-$i.jpg');
      }
      final fs = _FakeFilesystem(occupied: occupied);
      expect(
        () => resolveUploadDestination(
          filesystem: fs,
          directory: '/cwd',
          filename: 'photo.jpg',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('joins with the fake pathContext, not a hardcoded separator', () async {
      final fs = _FakeFilesystem(
        pathContext: p.Context(style: p.Style.windows),
      );
      final path = await resolveUploadDestination(
        filesystem: fs,
        directory: r'C:\cwd',
        filename: 'photo.jpg',
      );
      expect(path, r'C:\cwd\photo.jpg');
      expect(path, contains(r'\'));
      expect(path, isNot(contains('/')));
    });
  });
}
