import 'package:flutter/foundation.dart';

/// Workspace-scoped quick-open index rules: [excluded] directories never enter
/// the Ctrl+P index, [included] paths carve searchable subtrees back out of
/// the excluded ones.
///
/// Entries are workspace-root-relative (`common/convertor`), stored with `/`
/// separators regardless of backend. Both lists are normalized on
/// construction: trimmed, separators unified, leading `./` / `/` and trailing
/// `/` stripped, empties and duplicates dropped.
@immutable
class WorkspaceIndexDirs {
  const WorkspaceIndexDirs._({
    required this.excluded,
    required this.included,
  });

  const WorkspaceIndexDirs.empty()
    : excluded = const [],
      included = const [];

  factory WorkspaceIndexDirs({
    List<String> excluded = const [],
    List<String> included = const [],
  }) {
    return WorkspaceIndexDirs._(
      excluded: _normalizeAll(excluded),
      included: _normalizeAll(included),
    );
  }

  factory WorkspaceIndexDirs.fromJson(Object? json) {
    if (json is! Map) return const WorkspaceIndexDirs.empty();
    return WorkspaceIndexDirs(
      excluded: _stringList(json['excluded']),
      included: _stringList(json['included']),
    );
  }

  final List<String> excluded;
  final List<String> included;

  bool get isEmpty => excluded.isEmpty && included.isEmpty;

  Map<String, Object?> toJson() => {
    if (excluded.isNotEmpty) 'excluded': excluded,
    if (included.isNotEmpty) 'included': included,
  };

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return [for (final entry in raw) if (entry is String) entry];
  }

  static List<String> _normalizeAll(List<String> paths) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in paths) {
      final normalized = normalizeIndexDirRule(raw);
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      result.add(normalized);
    }
    return List.unmodifiable(result);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceIndexDirs &&
          listEquals(excluded, other.excluded) &&
          listEquals(included, other.included);

  @override
  int get hashCode => Object.hash(Object.hashAll(excluded), Object.hashAll(included));
}

/// Canonical form of one rule path: `/`-separated, no leading `./` or `/`, no
/// trailing separator; empty when the input carries no usable segments.
String normalizeIndexDirRule(String raw) {
  var path = raw.trim().replaceAll(r'\', '/');
  while (path.startsWith('./')) {
    path = path.substring(2);
  }
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path == '.') return ''; // a bare "." names the root itself
  if (path.startsWith('/')) return ''; // absolute paths are not rule inputs
  return path;
}
