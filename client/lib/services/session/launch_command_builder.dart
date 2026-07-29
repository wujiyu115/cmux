import 'dart:io';

import 'package:path/path.dart' as p;


class LaunchCommandBuilder {
  const LaunchCommandBuilder._();

  static List<String> splitArgs(String input) {
    final args = <String>[];
    final buffer = StringBuffer();
    String? quote;
    var escaping = false;

    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      if (escaping) {
        buffer.write(char);
        escaping = false;
        continue;
      }
      if (char == r'\') {
        escaping = true;
        continue;
      }
      if (quote != null) {
        if (char == quote) {
          quote = null;
        } else {
          buffer.write(char);
        }
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char.trim().isEmpty) {
        if (buffer.isNotEmpty) {
          args.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }
      buffer.write(char);
    }

    if (escaping) {
      buffer.write(r'\');
    }
    if (buffer.isNotEmpty) {
      args.add(buffer.toString());
    }
    return args;
  }

  static String normalizePathForCli(String path, {required bool useWslPaths}) {
    if (!useWslPaths) return path;
    return windowsPathToWsl(path) ?? path;
  }

  static String? windowsPathToWsl(String path) {
    final trimmed = path.trim();
    final uncMatch = RegExp(
      r'^\\+(?:wsl\.localhost|wsl\$)\\[^\\]+\\(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed.replaceAll('/', r'\'));
    if (uncMatch != null) {
      return '/${uncMatch.group(1)!.replaceAll(r'\', '/')}';
    }

    final match = RegExp(r'^([a-zA-Z]):[\\/]*(.*)$').firstMatch(trimmed);
    if (match == null) return null;
    final drive = match.group(1)!.toLowerCase();
    final rest = match.group(2)!.replaceAll('\\', '/');
    return rest.isEmpty ? '/mnt/$drive' : '/mnt/$drive/$rest';
  }

  /// Inverse of [windowsPathToWsl] for `/mnt/<drive>/...` paths.
  static String? wslPathToWindows(String path) {
    final trimmed = path.trim();
    if (!trimmed.startsWith('/')) return null;

    final normalized = p.Context(style: p.Style.posix).normalize(trimmed);
    final match = RegExp(r'^/mnt/([a-zA-Z])(?:/(.*))?$').firstMatch(normalized);
    if (match == null) return null;

    final drive = match.group(1)!.toUpperCase();
    final rest = match.group(2);
    if (rest == null || rest.isEmpty) {
      return '$drive:\\';
    }
    return p.normalize('$drive:\\${rest.replaceAll('/', r'\')}');
  }

  static String workingDirectoryForProcess(
    String workingDirectory, {
    required bool useWslPaths,
  }) {
    if (!useWslPaths) return workingDirectory;
    if (!Platform.isWindows) return workingDirectory;
    // Windows PTY wraps `wsl.exe`; CreateProcess cwd must be a native path.
    // Workspace dirs are passed separately via CLI args in WSL form.
    final userProfile = Platform.environment['USERPROFILE']?.trim();
    if (userProfile != null && userProfile.isNotEmpty) {
      return userProfile;
    }
    final systemRoot = Platform.environment['SystemRoot']?.trim();
    if (systemRoot != null && systemRoot.isNotEmpty) {
      return systemRoot;
    }
    return Directory.current.path;
  }

  static Map<String, String>? normalizeEnvironmentForCli(
    Map<String, String>? environment, {
    required bool useWslPaths,
  }) {
    if (environment == null || !useWslPaths) return environment;
    return {
      for (final entry in environment.entries)
        entry.key: normalizePathForCli(entry.value, useWslPaths: true),
    };
  }

}
