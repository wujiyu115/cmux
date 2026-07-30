import 'package:flutter/foundation.dart';

/// A workspace / group accent color chosen from a preset palette (index into a
/// theme-adaptive swatch list), mirroring [WorkspaceIconPreset].
///
/// Persisted as a bare non-negative int; `null` means "no accent" (fall back to
/// the theme primary).
@immutable
class WorkspaceAccentPreset {
  const WorkspaceAccentPreset(this.index);

  final int index;

  /// Decodes a bare int (or `{"index": int}` envelope). Returns null for any
  /// missing / malformed / negative value so old files stay compatible.
  static WorkspaceAccentPreset? fromJson(Object? json) {
    if (json is int) return json < 0 ? null : WorkspaceAccentPreset(json);
    if (json is Map) {
      final raw = json['index'];
      if (raw is int && raw >= 0) return WorkspaceAccentPreset(raw);
    }
    return null;
  }

  int toJson() => index;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceAccentPreset && other.index == index;

  @override
  int get hashCode => index.hashCode;
}
