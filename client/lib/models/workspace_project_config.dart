import 'package:flutter/foundation.dart';

/// Project-scoped bindings for a workspace (`project-config.json`).
///
/// Extension overrides map extension id -> forced on/off; absent keys follow
/// the global default.
@immutable
class WorkspaceProjectConfig {
  const WorkspaceProjectConfig({this.extensionOverrides = const {}});

  factory WorkspaceProjectConfig.fromJson(Map<String, Object?> json) {
    return WorkspaceProjectConfig(
      extensionOverrides: _decodeExtensionOverrides(json['extensionOverrides']),
    );
  }

  final Map<String, bool> extensionOverrides;

  static Map<String, bool> _decodeExtensionOverrides(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, bool>{};
    for (final entry in raw.entries) {
      final id = entry.key.toString().trim();
      if (id.isEmpty) continue;
      final value = entry.value;
      if (value is bool) {
        out[id] = value;
      }
    }
    return Map.unmodifiable(out);
  }

  WorkspaceProjectConfig copyWith({Map<String, bool>? extensionOverrides}) {
    return WorkspaceProjectConfig(
      extensionOverrides: extensionOverrides ?? this.extensionOverrides,
    );
  }

  /// Whether [extensionId] is forced on/off for this workspace, or null to
  /// follow the global default.
  bool? extensionOverrideFor(String extensionId) {
    return extensionOverrides[extensionId.trim()];
  }

  bool effectiveExtensionEnabled({
    required String extensionId,
    required Set<String> globalEnabled,
  }) {
    final override = extensionOverrideFor(extensionId);
    if (override != null) return override;
    return globalEnabled.contains(extensionId);
  }

  Map<String, Object?> toJson() {
    return {
      if (extensionOverrides.isNotEmpty)
        'extensionOverrides': {
          for (final entry in extensionOverrides.entries)
            entry.key: entry.value,
        },
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceProjectConfig &&
          mapEquals(extensionOverrides, other.extensionOverrides);

  @override
  int get hashCode => Object.hashAll(extensionOverrides.entries);
}
