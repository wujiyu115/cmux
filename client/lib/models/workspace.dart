import 'package:flutter/foundation.dart';

import '../utils/workspace/workspace_path_utils.dart';
import 'workspace_accent.dart';
import 'workspace_folder.dart';
import 'workspace_icon_ref.dart';
import 'workspace_topology.dart';

@immutable
class Workspace {
  const Workspace._({
    required this.workspaceId,
    required this.folders,
    this.display = '',
    this.defaultProfileId = '',
    this.icon = WorkspaceIconRef.auto,
    required this.createdAt,
    this.updatedAt = 0,
    this.sessionIds = const [],
    this.rootSandboxEnvOptIn = false,
    this.groupId = '',
    this.accent,
    this.defaultShell,
  });

  factory Workspace({
    required String workspaceId,
    List<WorkspaceFolder> folders = const [],
    String display = '',
    String defaultProfileId = '',
    WorkspaceIconRef icon = WorkspaceIconRef.auto,
    required int createdAt,
    int updatedAt = 0,
    List<String> sessionIds = const [],
    bool rootSandboxEnvOptIn = false,
    String groupId = '',
    WorkspaceAccentPreset? accent,
    String? defaultShell,
  }) {
    return Workspace._(
      workspaceId: workspaceId,
      folders: List.unmodifiable(folders),
      display: display,
      defaultProfileId: defaultProfileId,
      icon: icon,
      createdAt: createdAt,
      updatedAt: updatedAt,
      sessionIds: sessionIds,
      rootSandboxEnvOptIn: rootSandboxEnvOptIn,
      groupId: groupId,
      accent: accent,
      defaultShell: defaultShell,
    );
  }

  factory Workspace.fromJson(Map<String, Object?> json) {
    final ids = json['sessionIds'];
    final sessionIds = ids is List
        ? ids.map((e) => '$e').where((s) => s.isNotEmpty).toList()
        : const <String>[];
    return Workspace(
      workspaceId: json['workspaceId'] as String? ?? '',
      folders: foldersFromJson(json['folders']),
      display: json['display'] as String? ?? '',
      defaultProfileId: json['defaultProfileId'] as String? ?? '',
      icon: WorkspaceIconRef.fromJson(json['icon']),
      createdAt: json['createdAt'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
      sessionIds: sessionIds,
      rootSandboxEnvOptIn: json['rootSandboxEnvOptIn'] == true,
      groupId: json['groupId'] as String? ?? '',
      accent: WorkspaceAccentPreset.fromJson(json['accent']),
      defaultShell: (json['defaultShell'] as String?)?.trim().isNotEmpty == true
          ? (json['defaultShell'] as String).trim()
          : null,
    );
  }

  final String workspaceId;
  final List<WorkspaceFolder> folders;
  final String display;
  final String defaultProfileId;
  final WorkspaceIconRef icon;
  final int createdAt;
  final int updatedAt;
  final List<String> sessionIds;

  final bool rootSandboxEnvOptIn;

  /// Id of the [WorkspaceGroup] this workspace belongs to; `''` = ungrouped.
  final String groupId;

  /// Accent color preset for the nav sidebar / surface tabs; null = theme default.
  final WorkspaceAccentPreset? accent;

  /// Default terminal shell (executable path or special id); null = global default.
  final String? defaultShell;

  String get firstFolderPath => folders.isEmpty ? '' : folders.first.path;
  List<String> get extraFolderPaths => folders.length <= 1
      ? const []
      : folders.skip(1).map((f) => f.path).toList(growable: false);
  List<String> get folderPaths =>
      folders.map((f) => f.path).toList(growable: false);

  String get effectiveDisplay =>
      display.isNotEmpty ? display : _basename(firstFolderPath);

  /// Basename of [firstFolderPath]; empty when no primary directory is set.
  String get primaryDirectoryName => directoryName(firstFolderPath);

  static String directoryName(String path) => _basename(path);

  /// Reorders [folders] so [primaryPath] is first, or prepends an out-of-catalog
  /// path (e.g. a git worktree) while keeping the rest as additional directories.
  static List<WorkspaceFolder> foldersForPrimaryPath(
    List<WorkspaceFolder> folders,
    String primaryPath,
  ) {
    if (folders.isEmpty) {
      final primary = normalizeWorkspacePath(primaryPath);
      if (primary.isEmpty) return folders;
      return [WorkspaceFolder(path: primary)];
    }
    final primary = normalizeWorkspacePath(primaryPath);
    if (primary.isEmpty) return folders;

    final matchIndex = folders.indexWhere(
      (f) => workspacePathsEqual(f.path, primary),
    );
    if (matchIndex > 0) {
      final selected = folders[matchIndex];
      return [
        selected,
        ...folders.take(matchIndex),
        ...folders.skip(matchIndex + 1),
      ];
    }
    if (matchIndex == 0) return folders;

    final targetId =
        targetIdForFolderPaths(folders, [primary], matchSubpaths: true) ??
        folders.first.targetId;
    return [
      WorkspaceFolder(path: primary, targetId: targetId),
      ...folders,
    ];
  }

  static String _basename(String path) {
    if (path.isEmpty) return '';
    final parts = path.replaceAll(r'\', '/').split('/');
    return parts.isEmpty ? path : parts.last;
  }

  Workspace copyWith({
    String? workspaceId,
    List<WorkspaceFolder>? folders,
    String? display,
    String? defaultProfileId,
    WorkspaceIconRef? icon,
    int? createdAt,
    int? updatedAt,
    List<String>? sessionIds,
    bool? rootSandboxEnvOptIn,
    String? groupId,
    WorkspaceAccentPreset? accent,
    bool clearAccent = false,
    String? defaultShell,
    bool clearDefaultShell = false,
  }) {
    return Workspace(
      workspaceId: workspaceId ?? this.workspaceId,
      folders: folders ?? this.folders,
      display: display ?? this.display,
      defaultProfileId: defaultProfileId ?? this.defaultProfileId,
      icon: icon ?? this.icon,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sessionIds: sessionIds ?? this.sessionIds,
      rootSandboxEnvOptIn: rootSandboxEnvOptIn ?? this.rootSandboxEnvOptIn,
      groupId: groupId ?? this.groupId,
      accent: clearAccent ? null : (accent ?? this.accent),
      defaultShell: clearDefaultShell ? null : (defaultShell ?? this.defaultShell),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'workspaceId': workspaceId,
      'folders': folders.map((f) => f.toJson()).toList(),
      'display': display,
      if (defaultProfileId.isNotEmpty) 'defaultProfileId': defaultProfileId,
      if (icon.toJson() case final json?) 'icon': json,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'sessionIds': sessionIds,
      if (rootSandboxEnvOptIn) 'rootSandboxEnvOptIn': true,
      if (groupId.isNotEmpty) 'groupId': groupId,
      if (accent case final a?) 'accent': a.toJson(),
      if (defaultShell case final s?) 'defaultShell': s,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Workspace &&
            runtimeType == other.runtimeType &&
            workspaceId == other.workspaceId &&
            listEquals(folders, other.folders) &&
            display == other.display &&
            defaultProfileId == other.defaultProfileId &&
            icon == other.icon &&
            createdAt == other.createdAt &&
            updatedAt == other.updatedAt &&
            listEquals(sessionIds, other.sessionIds) &&
            rootSandboxEnvOptIn == other.rootSandboxEnvOptIn &&
            groupId == other.groupId &&
            accent == other.accent &&
            defaultShell == other.defaultShell;
  }

  @override
  int get hashCode => Object.hash(
    workspaceId,
    Object.hashAll(folders),
    display,
    defaultProfileId,
    icon,
    createdAt,
    updatedAt,
    Object.hashAll(sessionIds),
    rootSandboxEnvOptIn,
    groupId,
    accent,
    defaultShell,
  );
}

class WorkspacesIndex {
  const WorkspacesIndex({this.schemaVersion = 2, this.workspaces = const []});

  factory WorkspacesIndex.fromJson(Map<String, Object?> json) {
    final raw = json['workspaces'];
    final list = <Workspace>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, Object?>) {
          list.add(Workspace.fromJson(item));
        }
      }
    }
    return WorkspacesIndex(
      schemaVersion: json['schemaVersion'] as int? ?? 2,
      workspaces: list,
    );
  }

  final int schemaVersion;
  final List<Workspace> workspaces;

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'workspaces': workspaces.map((p) => p.toJson()).toList(),
    };
  }
}
