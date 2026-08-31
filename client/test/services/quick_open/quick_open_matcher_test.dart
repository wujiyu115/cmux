import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/quick_open/quick_open_index.dart';
import 'package:teampilot/services/quick_open/quick_open_matcher.dart';

QuickOpenFileEntry _entry(String relativePath) => QuickOpenFileEntry(
  path: '/repo/$relativePath',
  name: relativePath.split('/').last,
  relativePath: relativePath,
);

void main() {
  test('prefers a basename match over the path', () {
    final match = quickOpenMatch(_entry('read/read.dart'), 'read')!;
    expect(match.target, QuickOpenMatchTarget.name);
    // Highlight indexes address the basename, not the path.
    expect(match.indexes.first, 0);
  });

  test('falls back to the relative path when the name cannot match', () {
    final match = quickOpenMatch(_entry('lib/main.dart'), 'libmain')!;
    expect(match.target, QuickOpenMatchTarget.relativePath);
    expect(match.indexes.length, 'libmain'.length);
  });

  test('same-name files are disambiguated by a path query', () {
    final libSession = _entry('lib/session.dart');
    final docsSession = _entry('docs/session.dart');

    expect(quickOpenMatch(libSession, 'docsses'), isNull);
    expect(quickOpenMatch(docsSession, 'docsses'), isNotNull);
    expect(quickOpenMatch(libSession, 'libses'), isNotNull);
    expect(quickOpenMatch(docsSession, 'libses'), isNull);
  });

  test('query separators match Windows-style backslash paths', () {
    final entry = QuickOpenFileEntry(
      path: r'C:\repo\lib\main.dart',
      name: 'main.dart',
      relativePath: r'lib\main.dart',
    );

    final match = quickOpenMatch(entry, 'lib/main')!;

    expect(match.target, QuickOpenMatchTarget.relativePath);
    // One-to-one normalization keeps indexes valid on the original string:
    // `lib` + `\` + `main`.
    expect(
      match.indexes,
      List<int>.generate('lib/main'.length, (i) => i),
    );
  });

  test('returns null for an empty query or no match', () {
    final entry = _entry('lib/main.dart');
    expect(quickOpenMatch(entry, ''), isNull);
    expect(quickOpenMatch(entry, 'zzz'), isNull);
  });

  test('name matches outrank path matches for the same query', () {
    final nameHit = quickOpenMatch(_entry('x/dread.dart'), 'dread')!;
    final pathHit = quickOpenMatch(_entry('docs/read.dart'), 'dread')!;
    expect(nameHit.target, QuickOpenMatchTarget.name);
    expect(pathHit.target, QuickOpenMatchTarget.relativePath);
    expect(nameHit.score, greaterThan(pathHit.score));
  });
}
