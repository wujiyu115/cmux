import 'dart:io';

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/repositories/user_terminal_theme_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/theme/terminal/cmux_terminal_theme.dart';

CmuxTerminalTheme _makeTheme({required String name}) {
  return CmuxTerminalTheme(
    name: name,
    author: 'tester',
    isDark: true,
    background: const Color(0xFF1D1F21),
    foreground: const Color(0xFFC5C8C6),
    cursor: const Color(0xFFFFFFFF),
    selection: const Color(0xFF373B41),
    searchHit: const Color(0xFFF0C674),
    searchHitCurrent: const Color(0xFFB5BD68),
    searchHitFg: const Color(0xFF1D1F21),
    ansi: <Color>[
      for (var i = 0; i < 16; i++) Color(0xFF000000 | (i * 0x101010)),
    ],
  );
}

void main() {
  late Directory tempDir;
  late LocalFilesystem fs;
  late String themesDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('user_themes_test_');
    fs = LocalFilesystem();
    themesDir = p.join(tempDir.path, 'themes');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  UserTerminalThemeRepository repo() =>
      UserTerminalThemeRepository(fs: fs, directory: themesDir);

  test('save then loadAll round-trips the theme', () async {
    final saved = await repo().save(_makeTheme(name: 'My Theme'));
    expect(saved.id, 'my-theme');

    final loaded = await repo().loadAll();
    expect(loaded, hasLength(1));
    final theme = loaded.single;
    expect(theme.id, 'my-theme');
    expect(theme.name, 'My Theme');
    expect(theme.author, 'tester');
    expect(theme.isDark, isTrue);
    expect(theme.background.toARGB32(), 0xFF1D1F21);
    expect(theme.foreground.toARGB32(), 0xFFC5C8C6);
    expect(theme.ansi.map((c) => c.toARGB32()).toList(),
        _makeTheme(name: 'x').ansi.map((c) => c.toARGB32()).toList());
  });

  test('colliding with a built-in id gets a numeric suffix', () async {
    // "Dracula" is a built-in catalog theme (id "dracula").
    final saved = await repo().save(_makeTheme(name: 'Dracula'));
    expect(saved.id, 'dracula-2');
    expect(File(p.join(themesDir, 'dracula-2.json')).existsSync(), isTrue);
    expect(File(p.join(themesDir, 'dracula.json')).existsSync(), isFalse);
  });

  test('colliding between two user themes suffixes incrementally', () async {
    final first = await repo().save(_makeTheme(name: 'My Theme'));
    final second = await repo().save(_makeTheme(name: 'My Theme'));
    expect(first.id, 'my-theme');
    expect(second.id, 'my-theme-2');

    final ids = (await repo().loadAll()).map((t) => t.id).toList();
    expect(ids, containsAll(<String>['my-theme', 'my-theme-2']));
  });

  test('delete removes the theme', () async {
    final saved = await repo().save(_makeTheme(name: 'My Theme'));
    await repo().delete(saved.id);
    expect(await repo().loadAll(), isEmpty);
    expect(File(p.join(themesDir, 'my-theme.json')).existsSync(), isFalse);
  });

  test('corrupt file is skipped without throwing', () async {
    await repo().save(_makeTheme(name: 'Good Theme'));
    Directory(themesDir).createSync(recursive: true);
    File(p.join(themesDir, 'broken.json')).writeAsStringSync('{not valid json');

    final loaded = await repo().loadAll();
    expect(loaded.map((t) => t.id), <String>['good-theme']);
  });

  test('missing directory yields an empty list', () async {
    final loaded = await UserTerminalThemeRepository(
      fs: fs,
      directory: p.join(tempDir.path, 'does-not-exist'),
    ).loadAll();
    expect(loaded, isEmpty);
  });
}
