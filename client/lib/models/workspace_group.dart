import 'package:flutter/foundation.dart';

import 'workspace_accent.dart';

/// A named, ordered, collapsible grouping of workspaces in the nav sidebar.
///
/// Workspaces reference a group by [Workspace.groupId]; an empty group id means
/// "ungrouped" and is not represented by a [WorkspaceGroup].
@immutable
class WorkspaceGroup {
  const WorkspaceGroup({
    required this.id,
    this.name = '',
    this.order = 0,
    this.collapsed = false,
    this.accent,
  });

  factory WorkspaceGroup.fromJson(Map<String, Object?> json) {
    return WorkspaceGroup(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      order: json['order'] as int? ?? 0,
      collapsed: json['collapsed'] == true,
      accent: WorkspaceAccentPreset.fromJson(json['accent']),
    );
  }

  final String id;
  final String name;
  final int order;
  final bool collapsed;
  final WorkspaceAccentPreset? accent;

  WorkspaceGroup copyWith({
    String? id,
    String? name,
    int? order,
    bool? collapsed,
    WorkspaceAccentPreset? accent,
    bool clearAccent = false,
  }) {
    return WorkspaceGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      order: order ?? this.order,
      collapsed: collapsed ?? this.collapsed,
      accent: clearAccent ? null : (accent ?? this.accent),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'order': order,
      if (collapsed) 'collapsed': true,
      if (accent case final a?) 'accent': a.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WorkspaceGroup &&
            id == other.id &&
            name == other.name &&
            order == other.order &&
            collapsed == other.collapsed &&
            accent == other.accent;
  }

  @override
  int get hashCode => Object.hash(id, name, order, collapsed, accent);
}

/// Ordered set of [WorkspaceGroup]s persisted at `ui/workspace-groups.json`.
@immutable
class WorkspaceGroupsIndex {
  const WorkspaceGroupsIndex({this.groups = const []});

  factory WorkspaceGroupsIndex.fromJson(Map<String, Object?> json) {
    final raw = json['groups'];
    final list = <WorkspaceGroup>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, Object?>) {
          list.add(WorkspaceGroup.fromJson(item));
        }
      }
    }
    return WorkspaceGroupsIndex(groups: List.unmodifiable(list));
  }

  final List<WorkspaceGroup> groups;

  Map<String, Object?> toJson() {
    return {'groups': groups.map((g) => g.toJson()).toList()};
  }
}
