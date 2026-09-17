import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/quick_open/quick_open_overlay.dart';

void main() {
  test('splits a trailing line number off the query', () {
    expect(splitQuickOpenLineSuffix('foo.dart:42'), (query: 'foo.dart', line: 42));
    expect(splitQuickOpenLineSuffix('lib/a.dart:1'), (query: 'lib/a.dart', line: 1));
    expect(splitQuickOpenLineSuffix('a : 7'), (query: 'a', line: 7));
  });

  test('windows-style absolute path with drive keeps its colon', () {
    // `D:\x\a.dart` — the drive colon must not be eaten; only a TRAILING
    // `:digits` suffix splits.
    expect(splitQuickOpenLineSuffix('D:\\x\\a.dart'), (
      query: 'D:\\x\\a.dart',
      line: null,
    ));
  });

  test('no trailing number → line null, query trimmed', () {
    expect(splitQuickOpenLineSuffix('foo.dart'), (query: 'foo.dart', line: null));
    expect(splitQuickOpenLineSuffix('  foo.dart  '), (
      query: 'foo.dart',
      line: null,
    ));
  });

  test('bare `:123` is not a line suffix', () {
    expect(splitQuickOpenLineSuffix(':123'), (query: ':123', line: null));
  });

  test('non-digits suffix stays part of the query', () {
    expect(splitQuickOpenLineSuffix('foo:bar'), (query: 'foo:bar', line: null));
  });
}
