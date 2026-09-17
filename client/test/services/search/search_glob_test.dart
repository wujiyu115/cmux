import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/search/search_glob.dart';

void main() {
  group('SearchGlobSet', () {
    test('bare pattern matches basename in any directory', () {
      final set = SearchGlobSet('*.dart');
      expect(set.matches('lib/a.dart'), isTrue);
      expect(set.matches('deep/nested/b.dart'), isTrue);
      expect(set.matches('a.ts'), isFalse);
      expect(set.matches('dart'), isFalse);
    });

    test('pattern with slash anchors at path start', () {
      final set = SearchGlobSet('lib/*.dart');
      expect(set.matches('lib/a.dart'), isTrue);
      expect(set.matches('src/lib/a.dart'), isFalse);
    });

    test('double star spans directories', () {
      final set = SearchGlobSet('src/**');
      expect(set.matches('src/a.dart'), isTrue);
      expect(set.matches('src/deep/b.dart'), isTrue);
      expect(set.matches('lib/src/a.dart'), isFalse);

      final leading = SearchGlobSet('**/build/**');
      expect(leading.matches('build/out.js'), isTrue);
      expect(leading.matches('pkg/build/out.js'), isTrue);
      expect(leading.matches('pkg/src/a.dart'), isFalse);
    });

    test('question mark matches one non-separator char', () {
      final set = SearchGlobSet('a?.dart');
      expect(set.matches('ab.dart'), isTrue);
      expect(set.matches('abc.dart'), isFalse);
      expect(set.matches('a/.dart'), isFalse);
    });

    test('trailing slash matches directory prefix', () {
      final set = SearchGlobSet('build/');
      expect(set.matches('build/out.js'), isTrue);
      expect(set.matches('build/nested/out.js'), isTrue);
      expect(set.matches('src/build-out.js'), isFalse);
    });

    test('comma-separated patterns are any-match', () {
      final set = SearchGlobSet('*.dart, *.md');
      expect(set.matches('lib/a.dart'), isTrue);
      expect(set.matches('README.md'), isTrue);
      expect(set.matches('a.ts'), isFalse);
    });

    test('regex metacharacters are escaped', () {
      final set = SearchGlobSet('a+b.dart');
      expect(set.matches('a+b.dart'), isTrue);
      expect(set.matches('aab.dart'), isFalse);

      final dots = SearchGlobSet('a.b');
      expect(dots.matches('axb'), isFalse);
      expect(dots.matches('a.b'), isTrue);
    });

    test('empty and whitespace-only patterns are no-ops', () {
      final set = SearchGlobSet(' , ,');
      expect(set.isEmpty, isTrue);
      expect(set.matches('anything.dart'), isFalse);
    });
  });
}
