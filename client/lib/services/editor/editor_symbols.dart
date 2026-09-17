import 'package:equatable/equatable.dart';

import 'package:path/path.dart' as p;

/// One navigable symbol in an open document (outline / go-to-symbol).
///
/// v1 extraction is heuristic (line-pattern based, no tree-sitter): brace
/// languages, Python, Markdown headings, JSON/YAML keys. Deterministic and
/// testable; a tree-sitter query upgrade can replace [extractEditorSymbols]
/// behind the same shape later.
enum EditorSymbolKind { heading, type, callable, key }

class EditorSymbol extends Equatable {
  const EditorSymbol({
    required this.kind,
    required this.name,
    required this.line,
    required this.depth,
  });

  final EditorSymbolKind kind;

  /// Display name (class/function name, heading text, JSON key).
  final String name;

  /// 0-based line index of the definition.
  final int line;

  /// Nesting depth (indentation-based) for outline indentation.
  final int depth;

  @override
  List<Object?> get props => [kind, name, line, depth];
}

const _braceExts = {
  'dart', 'ts', 'tsx', 'js', 'jsx', 'java', 'kt', 'swift', 'scala',
  'c', 'h', 'cpp', 'hpp', 'cc', 'cs', 'go', 'rs', 'php',
};

const _callableKeywordBlocklist = {
  'if', 'else', 'for', 'while', 'switch', 'case', 'catch', 'finally',
  'return', 'throw', 'match', 'when', 'synchronized', 'lock', 'do', 'try',
  'loop', 'unsafe', 'using', 'with', 'await', 'yield',
};

/// Heuristic symbol extraction for [content] of [path].
List<EditorSymbol> extractEditorSymbols(String path, String content) {
  final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
  if (ext == 'md' || ext == 'markdown') return _markdownSymbols(content);
  if (ext == 'json') return _jsonSymbols(content);
  if (ext == 'yaml' || ext == 'yml') return _flatYamlSymbols(content);
  if (ext == 'py') return _pythonSymbols(content);
  if (_braceExts.contains(ext)) return _braceLanguageSymbols(content);
  return const [];
}

List<EditorSymbol> _markdownSymbols(String content) {
  final symbols = <EditorSymbol>[];
  var line = 0;
  for (final raw in LineSplitterLite.split(content)) {
    final m = RegExp(r'^(#{1,6})\s+(.+?)\s*#*$').firstMatch(raw);
    if (m != null) {
      symbols.add(
        EditorSymbol(
          kind: EditorSymbolKind.heading,
          name: m.group(2)!,
          line: line,
          depth: m.group(1)!.length - 1,
        ),
      );
    }
    line++;
  }
  return symbols;
}

List<EditorSymbol> _pythonSymbols(String content) {
  final symbols = <EditorSymbol>[];
  var line = 0;
  final def = RegExp(r'^(\s*)(?:async\s+)?(class|def)\s+(\w+)');
  for (final raw in LineSplitterLite.split(content)) {
    final m = def.firstMatch(raw);
    if (m != null) {
      symbols.add(
        EditorSymbol(
          kind: m.group(2) == 'class'
              ? EditorSymbolKind.type
              : EditorSymbolKind.callable,
          name: m.group(3)!,
          line: line,
          depth: m.group(1)!.length ~/ 4,
        ),
      );
    }
    line++;
  }
  return symbols;
}

/// Types + callables in brace languages (Dart/TS/Rust/Go/…). Comments and
/// control-flow keywords are excluded.
List<EditorSymbol> _braceLanguageSymbols(String content) {
  final symbols = <EditorSymbol>[];
  var line = 0;
  final type = RegExp(
    r'^(\s*)(?:@[\w.]+\s+)*(?:export\s+|declare\s+|default\s+|pub\s+|public\s+|private\s+|protected\s+|internal\s+|abstract\s+|final\s+|open\s+|sealed\s+|static\s+)*'
    r'(?:class|struct|enum|interface|trait|mixin|extension|module)\s+([\w<>,]+)',
  );
  final goType = RegExp(r'^type\s+(\w+)\s+(?:struct|interface)\b');
  final callableHead = RegExp(
    r'^(\s*)(?:@[\w.]+\s+)*(?:(?:export|declare|pub|public|private|protected|internal|static|const|final|async|override|abstract|extern|unsafe|virtual|inline|suspend|function|fun|fn|func|def)\s+)*'
    r'([\w<>?,.\[\]]+\s+)?(\w+)\s*(?:<[^>]*>)?\s*\([^;{=]*\)',
  );
  for (final raw in LineSplitterLite.split(content)) {
    final stripped = raw.trimLeft();
    if (stripped.startsWith('//') ||
        stripped.startsWith('/*') ||
        stripped.startsWith('*')) {
      line++;
      continue;
    }
    final typeMatch = type.firstMatch(raw);
    final goTypeMatch = goType.firstMatch(raw);
    final callableMatch = callableHead.firstMatch(raw);
    if (typeMatch != null) {
      symbols.add(
        EditorSymbol(
          kind: EditorSymbolKind.type,
          name: typeMatch.group(2)!,
          line: line,
          depth: typeMatch.group(1)!.length ~/ 2,
        ),
      );
    } else if (goTypeMatch != null) {
      symbols.add(
        EditorSymbol(
          kind: EditorSymbolKind.type,
          name: goTypeMatch.group(1)!,
          line: line,
          depth: 0,
        ),
      );
    } else if (callableMatch != null) {
      final name = callableMatch.group(3)!;
      final remainder = raw.substring(callableMatch.end).trim();
      // Body indicators: arrow body, or a `{` block with no `;` terminator
      // between the parens and it (return types like `: void {`,
      // `-> Self {`, `*Server {`, `async {`, `{}` all qualify).
      final hasBody = remainder.startsWith('=>') ||
          (remainder.contains('{') && !remainder.contains(';'));
      if (hasBody && !_callableKeywordBlocklist.contains(name)) {
        symbols.add(
          EditorSymbol(
            kind: EditorSymbolKind.callable,
            name: name,
            line: line,
            depth: callableMatch.group(1)!.length ~/ 2,
          ),
        );
      }
    }
    line++;
  }
  return symbols;
}

/// JSON top-level object/array keys (container values only — scalar keys
/// would drown the outline in a big JSON).
List<EditorSymbol> _jsonSymbols(String content) {
  final symbols = <EditorSymbol>[];
  var line = 0;
  final key = RegExp(r'^(\s*)"([^"]+)"\s*:\s*[{[]');
  for (final raw in LineSplitterLite.split(content)) {
    final m = key.firstMatch(raw);
    if (m != null) {
      final indent = m.group(1)!.length;
      if (indent <= 2) {
        symbols.add(
          EditorSymbol(
            kind: EditorSymbolKind.key,
            name: m.group(2)!,
            line: line,
            depth: indent ~/ 2,
          ),
        );
      }
    }
    line++;
  }
  return symbols;
}

/// YAML top-level keys (indent 0) plus one nesting level — deeper keys with
/// `-` lists etc. get noisy.
List<EditorSymbol> _flatYamlSymbols(String content) {
  final symbols = <EditorSymbol>[];
  var line = 0;
  final key = RegExp(r'^(\s*)([\w.-]+)\s*:\s*(?:$|\S)');
  for (final raw in LineSplitterLite.split(content)) {
    final m = key.firstMatch(raw);
    if (m != null) {
      final indent = m.group(1)!.length;
      if (indent <= 2) {
        symbols.add(
          EditorSymbol(
            kind: EditorSymbolKind.key,
            name: m.group(2)!,
            line: line,
            depth: indent ~/ 2,
          ),
        );
      }
    }
    line++;
  }
  return symbols;
}

/// Minimal line splitter (avoids importing dart:convert just for this).
class LineSplitterLite {
  static Iterable<String> split(String content) sync* {
    var start = 0;
    for (var i = 0; i < content.length; i++) {
      if (content.codeUnitAt(i) == 0x0A) {
        var end = i;
        if (end > start && content.codeUnitAt(end - 1) == 0x0D) end--;
        yield content.substring(start, end);
        start = i + 1;
      }
    }
    if (start < content.length) yield content.substring(start);
  }
}
