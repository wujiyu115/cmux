import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor_platform/language_registry.dart';

void main() {
  test('resolves .json to json pack', () {
    expect(LanguageRegistry.builtins().resolve('/x/a.json')?.id, 'json');
  });

  test('resolves first-wave extensions to their packs', () {
    final reg = LanguageRegistry.builtins();
    final cases = <String, String>{
      '/x/a.dart': 'dart',
      '/x/a.yaml': 'yaml',
      '/x/a.yml': 'yaml',
      '/x/a.md': 'markdown',
      '/x/a.markdown': 'markdown',
      '/x/a.py': 'python',
      '/x/a.rs': 'rust',
      '/x/a.ts': 'typescript',
      '/x/a.tsx': 'typescript',
      '/x/a.js': 'typescript',
      '/x/a.jsx': 'typescript',
      '/x/a.mjs': 'typescript',
      '/x/a.cjs': 'typescript',
      '/x/a.sh': 'bash',
      '/x/a.bash': 'bash',
      '/x/a.xml': 'xml',
      '/x/a.html': 'html',
      '/x/a.htm': 'html',
      '/x/a.toml': 'toml',
      '/x/a.css': 'css',
      '/x/a.lua': 'lua',
    };
    cases.forEach((path, id) {
      expect(reg.resolve(path)?.id, id, reason: '$path should resolve to $id');
    });
  });

  test('resolves second-wave extensions to their packs', () {
    final reg = LanguageRegistry.builtins();
    final cases = <String, String>{
      '/x/a.c': 'c',
      '/x/a.h': 'c',
      '/x/a.cpp': 'cpp',
      '/x/a.cc': 'cpp',
      '/x/a.cxx': 'cpp',
      '/x/a.hpp': 'cpp',
      '/x/a.java': 'java',
      '/x/a.go': 'go',
      '/x/a.cs': 'csharp',
      '/x/a.php': 'php',
      '/x/a.rb': 'ruby',
      '/x/a.kt': 'kotlin',
      '/x/a.kts': 'kotlin',
      '/x/a.swift': 'swift',
      '/x/a.sql': 'sql',
      '/x/a.scss': 'scss',
    };
    cases.forEach((path, id) {
      expect(reg.resolve(path)?.id, id, reason: '$path should resolve to $id');
    });
  });

  test('every builtin pack points at an existing highlights asset', () {
    for (final pack in LanguageRegistry.builtins().packs) {
      expect(
        pack.highlightsAsset,
        'assets/editor_languages/${pack.id}/highlights.scm',
        reason: 'unexpected highlights asset path for ${pack.id}',
      );
    }
  });

  test('resolve is case-insensitive on extension', () {
    expect(LanguageRegistry.builtins().resolve('/x/A.JSON')?.id, 'json');
  });

  test('unknown extension resolves to null', () {
    expect(LanguageRegistry.builtins().resolve('/x/a.unknown'), isNull);
  });

  test('compound suffixes fall back to the inner extension', () {
    final reg = LanguageRegistry.builtins();
    expect(reg.resolve('/x/config.yaml.template')?.id, 'yaml');
    expect(reg.resolve('/x/values.yml.sample')?.id, 'yaml');
    expect(reg.resolve('/x/deploy.sh.dist')?.id, 'bash');
    expect(reg.resolve('/x/archive.tar.gz'), isNull);
    expect(reg.resolve('/x/photo.png.orig'), isNull);
  });

  test('path with no extension resolves to null', () {
    expect(LanguageRegistry.builtins().resolve('/x/Makefile'), isNull);
  });
}
