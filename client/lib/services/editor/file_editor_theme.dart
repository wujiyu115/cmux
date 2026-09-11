import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../theme/app_typography_scale.dart';
import '../../theme/terminal_derived_scheme.dart';
import '../../theme/workspace_surface_layers.dart';
import '../editor_platform/editor_syntax_theme.dart';

/// Extensions we treat as plain text for in-app editing (allowlist).
///
/// Everything else opens with the system default app. Safer than a binary
/// blocklist: unknown formats (Office, media, …) never look "editable".
const kEditorTextExtensions = {
  'dart',
  'json',
  'yaml',
  'yml',
  'md',
  'markdown',
  'py',
  'rs',
  'ts',
  'tsx',
  'js',
  'jsx',
  'mjs',
  'cjs',
  'sh',
  'bash',
  'zsh',
  'fish',
  'xml',
  'html',
  'htm',
  'xhtml',
  'toml',
  'css',
  'scss',
  'sass',
  'less',
  // Other common text / code (no dedicated highlighter).
  'txt',
  'text',
  'log',
  'csv',
  'tsv',
  'sql',
  'c',
  'h',
  'cc',
  'cpp',
  'cxx',
  'hpp',
  'hh',
  'go',
  'mod',
  'sum',
  'java',
  'kt',
  'kts',
  'swift',
  'rb',
  'erb',
  'php',
  'vue',
  'svelte',
  'lua',
  'zig',
  'hs',
  'elm',
  'clj',
  'cljs',
  'ex',
  'exs',
  'ml',
  'mli',
  'fs',
  'fsx',
  'r',
  'pl',
  'pm',
  'awk',
  'gradle',
  'groovy',
  'tf',
  'hcl',
  'ini',
  'cfg',
  'conf',
  'config',
  'properties',
  'env',
  'plist',
  'svg',
  'graphql',
  'gql',
  'proto',
  'cmake',
  'ninja',
  'lock',
  'patch',
  'diff',
};

/// Extensionless files that are still plain text (checked case-insensitively).
const kEditorTextBasenames = {
  'dockerfile',
  'containerfile',
  'makefile',
  'gnumakefile',
  'cmakelists.txt',
  'license',
  'licence',
  'readme',
  'changelog',
  'gemfile',
  'rakefile',
  'procfile',
  'vagrantfile',
  'brewfile',
  'justfile',
};

/// Maximum file size loaded into the editor (bytes).
const kEditorMaxFileBytes = 2 * 1024 * 1024;

const kEditorImageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

/// Max image bytes loaded for in-app preview (separate from text editor cap).
const kEditorMaxImageBytes = 25 * 1024 * 1024;

/// Extensions we refuse to open in the editor without sniffing content.
///
/// Everything outside [kEditorTextExtensions] / [kEditorImageExtensions] /
/// this set is treated as *maybe text* and content-sniffed on open
/// ([bytesSeemBinary]), so custom text formats (`.sproto`, `.td`, …) open
/// fine while real binaries still fall through to the system default app.
const kEditorBinaryExtensions = {
  'exe', 'dll', 'so', 'dylib', 'o', 'a', 'lib', 'bin', 'obj', 'class',
  'jar', 'war', 'apk', 'dmg', 'msi', 'deb', 'rpm', 'wasm',
  'zip', 'tar', 'gz', 'tgz', 'bz2', 'xz', '7z', 'rar', 'zst', 'iso',
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp',
  'mp3', 'wav', 'flac', 'ogg', 'm4a', 'aac', 'wma',
  'mp4', 'mkv', 'avi', 'mov', 'webm', 'wmv', 'flv',
  'psd', 'ai', 'ico', 'tiff',
  'ttf', 'otf', 'woff', 'woff2', 'eot',
  'sqlite', 'db', 'pyc', 'pyo',
};

/// Whether [filePath] should open in the in-app text editor.
///
/// Compound suffixes fall back to inner segments: `config.yaml.template` is a
/// YAML text file, so the `yaml` segment makes it openable even though
/// `template` alone is not a known text extension.
bool isEditorOpenableFilePath(String filePath) {
  final base = p.basename(filePath).toLowerCase();
  var current = base;
  while (true) {
    final ext = p.extension(current).replaceFirst('.', '');
    if (ext.isEmpty) break;
    if (kEditorTextExtensions.contains(ext)) return true;
    current = p.basenameWithoutExtension(current);
  }
  return kEditorTextBasenames.contains(base);
}

bool isImagePreviewPath(String filePath) {
  final ext = p.extension(filePath).replaceFirst('.', '').toLowerCase();
  return ext.isNotEmpty && kEditorImageExtensions.contains(ext);
}

bool isKnownBinaryFilePath(String filePath) {
  final ext = p.extension(filePath).replaceFirst('.', '').toLowerCase();
  return ext.isNotEmpty && kEditorBinaryExtensions.contains(ext);
}

/// Leading bytes inspected by [bytesSeemBinary] (VSCode sniffs the same 512).
const kEditorBinarySniffBytes = 512;

/// Whether content looks binary: any NUL byte in the leading bytes.
///
/// UTF-8 / ASCII text never contains NUL. UTF-16 text does, but the editor
/// cannot decode UTF-16 anyway, so routing it to the system default app is
/// the correct outcome here.
bool bytesSeemBinary(List<int> bytes) {
  final limit = bytes.length < kEditorBinarySniffBytes
      ? bytes.length
      : kEditorBinarySniffBytes;
  for (var i = 0; i < limit; i++) {
    if (bytes[i] == 0) return true;
  }
  return false;
}

/// Whether [filePath] may open in the workbench center pane.
///
/// Known-text and image extensions open directly; unknown extensions are
/// optimistic (content sniffing in [EditorCubit.openFile] decides), so only
/// [kEditorBinaryExtensions] falls through to the system default app.
bool isWorkbenchOpenableFilePath(String filePath) =>
    isEditorOpenableFilePath(filePath) ||
    isImagePreviewPath(filePath) ||
    !isKnownBinaryFilePath(filePath);

/// Editor monospace size from [AppTypographyTheme.mono].
double fileEditorFontSize(BuildContext context) => context.appTypography.mono;

CodeEditorStyle codeEditorStyleFor(
  BuildContext context,
  String filePath, {
  CodeTokenProvider? tokenProvider,
  Color? backgroundColor,
}) {
  final cs = Theme.of(context).colorScheme;
  final fonts = context.tpFonts;
  final textScaler = MediaQuery.textScalerOf(context);
  // Syntax colours follow the active terminal theme's ANSI palette on every
  // colour preset (not only the terminal-derived one), as long as its
  // luminance matches the editor — a light terminal theme in a dark UI would
  // paint unreadable scopes. Chrome stays preset-derived regardless.
  final brightness = Theme.of(context).brightness;
  final terminalTheme = Theme.of(
    context,
  ).extension<TerminalThemeExtension>()?.theme;
  final editorBackground = backgroundColor ?? cs.workspaceCode;
  final theme =
      terminalTheme != null &&
          terminalTheme.isLightByLuminance == (brightness == Brightness.light)
      ? EditorSyntaxTheme.fromTerminalTheme(
          terminalTheme,
          background: editorBackground,
        )
      : EditorSyntaxTheme.forBrightness(brightness);
  return CodeEditorStyle(
    fontSize: textScaler.scale(fileEditorFontSize(context)),
    fontHeight: 1.35,
    fontFamily: fonts.monoFontFamily,
    fontFamilyFallback: fonts.monoFontFamilyFallback,
    textColor: cs.onSurface,
    backgroundColor: editorBackground,
    selectionColor: cs.primary.withValues(alpha: 0.28),
    highlightColor: cs.tertiary.withValues(alpha: 0.35),
    cursorColor: cs.primary,
    cursorLineColor: cs.primary.withValues(alpha: 0.12),
    tokenProvider: tokenProvider,
    syntaxTheme: theme.asStyleMap(),
  );
}
