import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/shell_quote.dart';

void main() {
  test('leaves a plain path alone', () {
    // Quoting an already-safe path would be noise in the composer.
    expect(shellQuotePath('/home/dev/app/photo.jpg'), '/home/dev/app/photo.jpg');
  });

  test('leaves dots, dashes and underscores alone', () {
    expect(shellQuotePath('/a/b-c/d_e.f.jpg'), '/a/b-c/d_e.f.jpg');
  });

  test('quotes a path containing a space', () {
    // The whole reason this exists: unquoted, the shell splits this into two
    // arguments and the command fails.
    expect(
      shellQuotePath('/Users/me/My Project/photo.jpg'),
      "'/Users/me/My Project/photo.jpg'",
    );
  });

  test('quotes shell metacharacters', () {
    for (final path in [
      '/a/b\$c',
      '/a/b`c',
      '/a/b&c',
      '/a/b;c',
      '/a/b|c',
      '/a/b(c)',
      '/a/b*c',
      '/a/b?c',
      '/a/b#c',
      '/a/b!c',
      '/a/b\nc',
      '/a/b\tc',
    ]) {
      expect(shellQuotePath(path), startsWith("'"), reason: path);
      expect(shellQuotePath(path), endsWith("'"), reason: path);
    }
  });

  test('escapes an embedded single quote', () {
    // Inside single quotes nothing is special except the quote itself, so it
    // has to be closed, escaped, and reopened.
    expect(shellQuotePath("/a/it's/b.jpg"), r"'/a/it'\''s/b.jpg'");
  });

  test('escapes several embedded single quotes', () {
    expect(shellQuotePath("/a/'/'/b"), r"'/a/'\''/'\''/b'");
  });

  test('quotes a path made only of a single quote', () {
    expect(shellQuotePath("'"), r"''\'''");
  });

  test('quotes an empty string rather than emitting nothing', () {
    // An empty bare word would vanish from the command line; '' is one empty
    // argument, which is at least visible.
    expect(shellQuotePath(''), "''");
  });

  test('quotes a non-ASCII path', () {
    // Most shells cope, but the safe set is deliberately ASCII-only so we never
    // have to reason about locale-dependent word splitting.
    expect(shellQuotePath('/a/照片.jpg'), "'/a/照片.jpg'");
  });
}
