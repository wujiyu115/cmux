import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:teampilot_tree_sitter/teampilot_tree_sitter.dart';
import 'package:test/test.dart';

/// One smoke case per bundled grammar: parse a tiny sample and assert the
/// requested capture shows up, which proves the grammar + its external scanner
/// linked into the native asset and produce a usable tree.
class _GrammarCase {
  const _GrammarCase(this.id, this.language, this.source, this.query, this.capture);

  final String id;
  final TsLanguage Function() language;
  final String source;
  final String query;
  final String capture;
}

final _cases = <_GrammarCase>[
  _GrammarCase('json', TsLanguage.json, '{"a": 1}', '(string) @string', 'string'),
  _GrammarCase(
    'dart',
    TsLanguage.dart,
    'void main() {}',
    '(identifier) @id',
    'id',
  ),
  _GrammarCase('yaml', TsLanguage.yaml, 'a: 1\nb: two\n', '(block_mapping_pair) @pair', 'pair'),
  _GrammarCase(
    'markdown',
    TsLanguage.markdown,
    '# Heading\n\ntext\n',
    '(atx_heading) @heading',
    'heading',
  ),
  _GrammarCase(
    'python',
    TsLanguage.python,
    'def f():\n    return 1\n',
    '(function_definition) @fn',
    'fn',
  ),
  _GrammarCase(
    'rust',
    TsLanguage.rust,
    'fn main() {}',
    '(function_item) @fn',
    'fn',
  ),
  _GrammarCase(
    'typescript',
    TsLanguage.typescript,
    'const x: number = 1;',
    '(lexical_declaration) @decl',
    'decl',
  ),
  _GrammarCase(
    'bash',
    TsLanguage.bash,
    'echo hello\n',
    '(command) @cmd',
    'cmd',
  ),
  _GrammarCase(
    'xml',
    TsLanguage.xml,
    '<root><child>x</child></root>',
    '(element) @el',
    'el',
  ),
  _GrammarCase(
    'toml',
    TsLanguage.toml,
    'key = "value"\n',
    '(pair) @pair',
    'pair',
  ),
  _GrammarCase(
    'css',
    TsLanguage.css,
    'a { color: red; }',
    '(rule_set) @rule',
    'rule',
  ),
  _GrammarCase(
    'lua',
    TsLanguage.lua,
    'function f() end\n',
    '(function_declaration) @fn',
    'fn',
  ),
  _GrammarCase(
    'c',
    TsLanguage.c,
    'int main() { return 0; }\n',
    '(function_definition) @fn',
    'fn',
  ),
  _GrammarCase(
    'cpp',
    TsLanguage.cpp,
    'int main() { return 0; }\n',
    '(function_definition) @fn',
    'fn',
  ),
  _GrammarCase(
    'java',
    TsLanguage.java,
    'class A {}\n',
    '(class_declaration) @cls',
    'cls',
  ),
  _GrammarCase(
    'go',
    TsLanguage.go,
    'package main\n',
    '(package_clause) @pkg',
    'pkg',
  ),
  _GrammarCase(
    'csharp',
    TsLanguage.csharp,
    'class A {}\n',
    '(class_declaration) @cls',
    'cls',
  ),
  _GrammarCase(
    'php',
    TsLanguage.php,
    '<?php\nfunction f() {}\n',
    '(function_definition) @fn',
    'fn',
  ),
  _GrammarCase(
    'ruby',
    TsLanguage.ruby,
    'def f\nend\n',
    '(method) @m',
    'm',
  ),
  _GrammarCase(
    'kotlin',
    TsLanguage.kotlin,
    'fun f() {}\n',
    '(function_declaration) @fn',
    'fn',
  ),
  _GrammarCase(
    'swift',
    TsLanguage.swift,
    'func f() {}\n',
    '(function_declaration) @fn',
    'fn',
  ),
  _GrammarCase(
    'sql',
    TsLanguage.sql,
    'SELECT a FROM b;\n',
    '(identifier) @id',
    'id',
  ),
  _GrammarCase(
    'html',
    TsLanguage.html,
    '<p>x</p>',
    '(element) @el',
    'el',
  ),
  _GrammarCase(
    'scss',
    TsLanguage.scss,
    'a { color: red; }\n',
    '(rule_set) @rule',
    'rule',
  ),
  _GrammarCase(
    'dockerfile',
    TsLanguage.dockerfile,
    'FROM alpine\nRUN echo hi\n',
    '(from_instruction) @from',
    'from',
  ),
  _GrammarCase(
    'make',
    TsLanguage.make,
    'all:\n\techo hi\n',
    '(rule) @rule',
    'rule',
  ),
  _GrammarCase(
    'td',
    TsLanguage.td,
    '# schema\nUser (1) {\n  name string\n  friends <User, 2>\n}\nPostureMap <integer, PostureItem>\n',
    '(type_definition) @td',
    'td',
  ),
  _GrammarCase(
    'sproto',
    TsLanguage.sproto,
    '# protocol\nenter_home 1 {\n  request {\n    uuid 0 : string\n  }\n  response {\n    errcode 0 : integer\n  }\n}\n',
    '(protocol) @proto',
    'proto',
  ),
];

void main() {
  for (final c in _cases) {
    test('parses_${c.id}_smoke', () {
      final lang = c.language();
      final parser = TsParser()..setLanguage(lang);
      final bytes = utf8.encode(c.source);
      final tree = parser.parseUtf8(Uint8List.fromList(bytes));
      final query = TsQuery(lang, c.query);
      final caps = query.captures(tree, startByte: 0, endByte: bytes.length);
      expect(
        caps.any((cap) => cap.name == c.capture),
        isTrue,
        reason: 'expected a @${c.capture} capture for ${c.id}',
      );

      query.dispose();
      tree.dispose();
      parser.dispose();
    });
  }

  // Runs the app-shipped TD highlights query against a sample covering every
  // TD construct, asserting each capture kind fires. Guards the query from
  // silently matching nothing after grammar edits.
  test('td_highlights_captures_all_scopes', () {
    const source = '# schema\n'
        'User (1) {\n'
        '  name string\n'
        '  age number\n'
        '  tags [string]\n'
        '  friends <User, 2>\n'
        '  cave <number, <string, boolean>>\n'
        '}\n'
        'PostureMap <integer, PostureItem>\n';
    final querySource = File(
      '../../assets/editor_languages/td/highlights.scm',
    ).readAsStringSync();
    final lang = TsLanguage.td();
    final parser = TsParser()..setLanguage(lang);
    final bytes = utf8.encode(source);
    final tree = parser.parseUtf8(Uint8List.fromList(bytes));
    final query = TsQuery(lang, querySource);
    final caps = query.captures(tree, startByte: 0, endByte: bytes.length);
    final names = caps.map((cap) => cap.name).toSet();
    expect(names, containsAll(['comment', 'keyword', 'constant', 'number', 'punctuation']));
    // Field names are intentionally uncaptured (vscode-td leaves them plain),
    // so the primitive types dominate the keyword captures.
    expect(caps.where((cap) => cap.name == 'keyword').length, greaterThan(8));

    query.dispose();
    tree.dispose();
    parser.dispose();
  });

  // Runs the app-shipped sproto highlights query against a sample covering
  // every sproto construct, asserting each capture kind fires. Guards the
  // query from silently matching nothing after grammar edits.
  test('sproto_highlights_captures_all_scopes', () {
    const source = '# protocol\n'
        '.PlayerHome {\n'
        '  uuid 0 : string\n'
        '  weight 2: double\n'
        '  locked 6 : boolean\n'
        '  changes 1 : *bag.BagChange\n'
        '  counts 3: *BuildCount()\n'
        '  areas 2 : *PaintAreaMap(paint_id)\n'
        '  pos 4 : integer(2)\n'
        '  inner 5 : home.PlayerHome\n'
        '}\n'
        'enter_home 349 {\n'
        '  request {\n'
        '    uuid 0 : string\n'
        '  }\n'
        '  response {\n'
        '    errcode 0 : integer\n'
        '  }\n'
        '}\n'
        'notify_only 350 {\n'
        '  request nil\n'
        '}\n';
    final querySource = File(
      '../../assets/editor_languages/sproto/highlights.scm',
    ).readAsStringSync();
    final lang = TsLanguage.sproto();
    final parser = TsParser()..setLanguage(lang);
    final bytes = utf8.encode(source);
    final tree = parser.parseUtf8(Uint8List.fromList(bytes));
    final query = TsQuery(lang, querySource);
    final caps = query.captures(tree, startByte: 0, endByte: bytes.length);
    final names = caps.map((cap) => cap.name).toSet();
    expect(
      names,
      containsAll([
        'comment',
        'keyword',
        'constant',
        'number',
        'type',
        'function',
        'string',
        'punctuation',
      ]),
    );
    // Field names are intentionally uncaptured (sproto-support leaves them
    // plain), so the builtin types dominate the keyword captures.
    expect(caps.where((cap) => cap.name == 'keyword').length, greaterThan(5));

    query.dispose();
    tree.dispose();
    parser.dispose();
  });
}
