import 'package:teampilot/services/editor_platform/language_pack.dart';

/// Resolves file paths to [LanguagePack]s. Unknown extensions resolve to
/// `null` — callers must not substitute a different language's grammar as a
/// stand-in.
class LanguageRegistry {
  LanguageRegistry(List<LanguagePack> packs) : _packs = List.unmodifiable(packs);

  /// Built-in packs shipped with the app.
  factory LanguageRegistry.builtins() {
    return LanguageRegistry(const [
      LanguagePack(
        id: 'json',
        extensions: {'json'},
        grammarId: 'json',
        highlightsAsset: 'assets/editor_languages/json/highlights.scm',
      ),
      LanguagePack(
        id: 'dart',
        extensions: {'dart'},
        grammarId: 'dart',
        highlightsAsset: 'assets/editor_languages/dart/highlights.scm',
      ),
      LanguagePack(
        id: 'yaml',
        extensions: {'yaml', 'yml'},
        grammarId: 'yaml',
        highlightsAsset: 'assets/editor_languages/yaml/highlights.scm',
      ),
      LanguagePack(
        id: 'markdown',
        extensions: {'md', 'markdown'},
        grammarId: 'markdown',
        highlightsAsset: 'assets/editor_languages/markdown/highlights.scm',
      ),
      LanguagePack(
        id: 'python',
        extensions: {'py'},
        grammarId: 'python',
        highlightsAsset: 'assets/editor_languages/python/highlights.scm',
      ),
      LanguagePack(
        id: 'rust',
        extensions: {'rs'},
        grammarId: 'rust',
        highlightsAsset: 'assets/editor_languages/rust/highlights.scm',
      ),
      // The tsx grammar backs .ts/.tsx and also handles .js/.jsx/.mjs/.cjs.
      LanguagePack(
        id: 'typescript',
        extensions: {'ts', 'tsx', 'js', 'jsx', 'mjs', 'cjs'},
        grammarId: 'typescript',
        highlightsAsset: 'assets/editor_languages/typescript/highlights.scm',
      ),
      LanguagePack(
        id: 'bash',
        extensions: {'sh', 'bash'},
        grammarId: 'bash',
        highlightsAsset: 'assets/editor_languages/bash/highlights.scm',
      ),
      // One xml pack covers .xml; .html/.htm resolve to the dedicated html
      // pack below.
      LanguagePack(
        id: 'xml',
        extensions: {'xml'},
        grammarId: 'xml',
        highlightsAsset: 'assets/editor_languages/xml/highlights.scm',
      ),
      LanguagePack(
        id: 'toml',
        extensions: {'toml'},
        grammarId: 'toml',
        highlightsAsset: 'assets/editor_languages/toml/highlights.scm',
      ),
      LanguagePack(
        id: 'css',
        extensions: {'css'},
        grammarId: 'css',
        highlightsAsset: 'assets/editor_languages/css/highlights.scm',
      ),
      LanguagePack(
        id: 'lua',
        extensions: {'lua'},
        grammarId: 'lua',
        highlightsAsset: 'assets/editor_languages/lua/highlights.scm',
      ),
      LanguagePack(
        id: 'c',
        extensions: {'c', 'h'},
        grammarId: 'c',
        highlightsAsset: 'assets/editor_languages/c/highlights.scm',
      ),
      LanguagePack(
        id: 'cpp',
        extensions: {'cpp', 'cc', 'cxx', 'hpp', 'hh', 'hxx'},
        grammarId: 'cpp',
        highlightsAsset: 'assets/editor_languages/cpp/highlights.scm',
      ),
      LanguagePack(
        id: 'java',
        extensions: {'java'},
        grammarId: 'java',
        highlightsAsset: 'assets/editor_languages/java/highlights.scm',
      ),
      LanguagePack(
        id: 'go',
        extensions: {'go'},
        grammarId: 'go',
        highlightsAsset: 'assets/editor_languages/go/highlights.scm',
      ),
      LanguagePack(
        id: 'csharp',
        extensions: {'cs'},
        grammarId: 'csharp',
        highlightsAsset: 'assets/editor_languages/csharp/highlights.scm',
      ),
      LanguagePack(
        id: 'php',
        extensions: {'php'},
        grammarId: 'php',
        highlightsAsset: 'assets/editor_languages/php/highlights.scm',
      ),
      LanguagePack(
        id: 'ruby',
        extensions: {'rb'},
        grammarId: 'ruby',
        highlightsAsset: 'assets/editor_languages/ruby/highlights.scm',
      ),
      LanguagePack(
        id: 'kotlin',
        extensions: {'kt', 'kts'},
        grammarId: 'kotlin',
        highlightsAsset: 'assets/editor_languages/kotlin/highlights.scm',
      ),
      LanguagePack(
        id: 'swift',
        extensions: {'swift'},
        grammarId: 'swift',
        highlightsAsset: 'assets/editor_languages/swift/highlights.scm',
      ),
      LanguagePack(
        id: 'sql',
        extensions: {'sql'},
        grammarId: 'sql',
        highlightsAsset: 'assets/editor_languages/sql/highlights.scm',
      ),
      LanguagePack(
        id: 'html',
        extensions: {'html', 'htm'},
        grammarId: 'html',
        highlightsAsset: 'assets/editor_languages/html/highlights.scm',
      ),
      LanguagePack(
        id: 'scss',
        extensions: {'scss'},
        grammarId: 'scss',
        highlightsAsset: 'assets/editor_languages/scss/highlights.scm',
      ),
    ]);
  }

  final List<LanguagePack> _packs;

  /// All registered packs, in registration order.
  List<LanguagePack> get packs => _packs;

  /// Looks up the pack for [path] by basename, then by lowercase extension
  /// (without the leading dot). Compound suffixes fall back to inner segments:
  /// `config.yaml.template` resolves via its `yaml` segment. Returns `null`
  /// when no pack claims this path.
  LanguagePack? resolve(String path) {
    final basename = _basename(path);
    for (final pack in _packs) {
      if (pack.filenames.contains(basename)) {
        return pack;
      }
    }

    var current = basename;
    while (true) {
      final extension = _extension(current);
      if (extension == null) {
        return null;
      }
      for (final pack in _packs) {
        if (pack.extensions.contains(extension)) {
          return pack;
        }
      }
      final dotIndex = current.lastIndexOf('.');
      if (dotIndex <= 0) return null;
      current = current.substring(0, dotIndex);
    }
  }

  /// Looks up a registered pack by its [LanguagePack.id].
  LanguagePack? byId(String id) {
    for (final pack in _packs) {
      if (pack.id == id) {
        return pack;
      }
    }
    return null;
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final slashIndex = normalized.lastIndexOf('/');
    return slashIndex == -1 ? normalized : normalized.substring(slashIndex + 1);
  }

  static String? _extension(String basename) {
    final dotIndex = basename.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == basename.length - 1) {
      return null;
    }
    return basename.substring(dotIndex + 1).toLowerCase();
  }
}
