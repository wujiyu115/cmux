import 'package:flutter/foundation.dart';

import 'session_continue_overrides.dart';
import 'simple_launch_identity.dart';
import 'cli_tool.dart';
import 'workspace_folder.dart';
import 'workspace_topology.dart';

enum AppSessionLaunchState { created, started }

@immutable
class AppSession {
  const AppSession._({
    required this.sessionId,
    required this.workspaceId,
    required this.folders,
    this.memberTargets = const {},
    this.display = '',
    this.profileId = '',
    this.cli,
    this.provider = '',
    this.model = '',
    this.effort = '',
    this.presetId = '',
    this.launchState = AppSessionLaunchState.created,
    required this.createdAt,
    this.updatedAt = 0,
    this.pinned = false,
    this.sortOrder = 0,
    this.continueOverrides = const SessionContinueOverrides(),
  });

  factory AppSession({
    required String sessionId,
    required String workspaceId,
    List<WorkspaceFolder> folders = const [],
    Map<String, String> memberTargets = const {},
    String display = '',
    String profileId = '',
    CliTool? cli,
    String provider = '',
    String model = '',
    String effort = '',
    String presetId = '',
    AppSessionLaunchState launchState = AppSessionLaunchState.created,
    required int createdAt,
    int updatedAt = 0,
    bool pinned = false,
    int sortOrder = 0,
    SessionContinueOverrides continueOverrides =
        const SessionContinueOverrides(),
  }) {
    return AppSession._(
      sessionId: sessionId,
      workspaceId: workspaceId,
      folders: List.unmodifiable(folders),
      memberTargets: Map.unmodifiable({
        for (final e in memberTargets.entries)
          if (e.key.trim().isNotEmpty && e.value.trim().isNotEmpty)
            e.key.trim(): e.value.trim(),
      }),
      display: display,
      profileId: profileId,
      cli: cli,
      provider: provider.trim(),
      model: model.trim(),
      effort: effort.trim(),
      presetId: presetId.trim(),
      launchState: launchState,
      createdAt: createdAt,
      updatedAt: updatedAt,
      pinned: pinned,
      sortOrder: sortOrder,
      continueOverrides: continueOverrides,
    );
  }

  factory AppSession.fromJson(Map<String, Object?> json) {
    final launchRaw = json['launchState'] as String? ?? 'created';
    final launch = AppSessionLaunchState.values.firstWhere(
      (e) => e.name == launchRaw,
      orElse: () => AppSessionLaunchState.created,
    );
    final targetsRaw = json['memberTargets'];
    final targets = targetsRaw is Map
        ? <String, String>{
            for (final e in targetsRaw.entries)
              if ('${e.key}'.trim().isNotEmpty &&
                  '${e.value}'.trim().isNotEmpty)
                '${e.key}'.trim(): '${e.value}'.trim(),
          }
        : const <String, String>{};
    return AppSession(
      sessionId: json['sessionId'] as String? ?? '',
      workspaceId: json['workspaceId'] as String? ?? '',
      folders: foldersFromJson(json['folders']),
      memberTargets: targets,
      display: json['display'] as String? ?? '',
      profileId: json['profileId'] as String? ?? '',
      cli: CliTool.tryParse(json['cli'] as String?),
      provider: json['provider'] as String? ?? '',
      model: json['model'] as String? ?? '',
      effort: json['effort'] as String? ?? '',
      presetId: json['presetId'] as String? ?? '',
      launchState: launch,
      createdAt: json['createdAt'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
      pinned: json['pinned'] as bool? ?? false,
      sortOrder: json['sortOrder'] as int? ?? 0,
      continueOverrides: SessionContinueOverrides.fromJson(
        json['continueOverrides'] is Map
            ? Map<String, Object?>.from(json['continueOverrides'] as Map)
            : null,
      ),
    );
  }

  final String sessionId;
  final String workspaceId;
  final List<WorkspaceFolder> folders;

  /// Mixed workspace: runtime instance id → machine target id.
  final Map<String, String> memberTargets;

  final String display;

  String get firstFolderPath => folders.isEmpty ? '' : folders.first.path;
  List<String> get extraFolderPaths => folders.length <= 1
      ? const []
      : folders.skip(1).map((f) => f.path).toList(growable: false);
  List<String> get folderPaths =>
      folders.map((f) => f.path).toList(growable: false);

  /// Working directory + add-dirs for [memberId] against [folders].
  ({String workingDirectory, List<String> addDirs}) workDirsForMember(
    String? memberId, {
    required List<WorkspaceFolder> folders,
  }) {
    if (memberId == null || memberId.trim().isEmpty) {
      return personalWorkDirsForPrimaryPath(folders, firstFolderPath);
    }
    final targetId = memberTargetForInstanceId(memberTargets, memberId);
    if (targetId == null) {
      return (workingDirectory: firstFolderPath, addDirs: extraFolderPaths);
    }
    final work = memberWorkDirsForTarget(folders, targetId);
    if (work.workingDirectory.isEmpty) {
      return (workingDirectory: firstFolderPath, addDirs: extraFolderPaths);
    }
    return work;
  }

  final String profileId;
  final CliTool? cli;

  /// Simple launch: denormalized provider/model/effort (see [simpleIdentity]).
  final String provider;
  final String model;
  final String effort;

  /// Simple launch: provenance of the global CLI preset chosen at create.
  final String presetId;


  final AppSessionLaunchState launchState;
  final int createdAt;
  final int updatedAt;
  final bool pinned;
  final int sortOrder;

  /// Session-scoped continue chrome: permission + per-member model overrides.
  final SessionContinueOverrides continueOverrides;

  /// Denormalized launch identity for this session.
  SimpleLaunchIdentity get simpleIdentity {
    final resolvedCli = cli ?? CliTool.claude;
    var resolvedProvider = provider.trim();
    if (resolvedProvider.isEmpty) {
      resolvedProvider =
          SimpleLaunchIdentity.officialProviderIdFor(resolvedCli) ?? '';
    }
    return SimpleLaunchIdentity(
      cli: resolvedCli,
      provider: resolvedProvider,
      model: model.trim(),
      effort: effort.trim(),
      presetId: presetId.trim(),
    );
  }

  String resolveDisplayTitle(String whenDisplayEmpty) =>
      display.isNotEmpty ? display : whenDisplayEmpty;

  AppSession copyWith({
    String? sessionId,
    String? workspaceId,
    List<WorkspaceFolder>? folders,
    Map<String, String>? memberTargets,
    String? display,
    String? profileId,
    CliTool? cli,
    String? provider,
    String? model,
    String? effort,
    String? presetId,
    AppSessionLaunchState? launchState,
    int? createdAt,
    int? updatedAt,
    bool? pinned,
    int? sortOrder,
    SessionContinueOverrides? continueOverrides,
  }) {
    return AppSession(
      sessionId: sessionId ?? this.sessionId,
      workspaceId: workspaceId ?? this.workspaceId,
      folders: folders ?? this.folders,
      memberTargets: memberTargets ?? this.memberTargets,
      display: display ?? this.display,
      profileId: profileId ?? this.profileId,
      cli: cli ?? this.cli,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      effort: effort ?? this.effort,
      presetId: presetId ?? this.presetId,
      launchState: launchState ?? this.launchState,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pinned: pinned ?? this.pinned,
      sortOrder: sortOrder ?? this.sortOrder,
      continueOverrides: continueOverrides ?? this.continueOverrides,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'schemaVersion': 2,
      'sessionId': sessionId,
      'workspaceId': workspaceId,
      'folders': folders.map((f) => f.toJson()).toList(),
      if (memberTargets.isNotEmpty) 'memberTargets': memberTargets,
      'display': display,
      if (profileId.isNotEmpty) 'profileId': profileId,
      if (cli != null) 'cli': cli!.value,
      if (provider.isNotEmpty) 'provider': provider,
      if (model.isNotEmpty) 'model': model,
      if (effort.isNotEmpty) 'effort': effort,
      if (presetId.isNotEmpty) 'presetId': presetId,
      'launchState': launchState.name,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'pinned': pinned,
      if (sortOrder != 0) 'sortOrder': sortOrder,
      if (continueOverrides != const SessionContinueOverrides())
        'continueOverrides': continueOverrides.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppSession &&
            runtimeType == other.runtimeType &&
            sessionId == other.sessionId &&
            workspaceId == other.workspaceId &&
            listEquals(folders, other.folders) &&
            mapEquals(memberTargets, other.memberTargets) &&
            display == other.display &&
            profileId == other.profileId &&
            cli == other.cli &&
            provider == other.provider &&
            model == other.model &&
            effort == other.effort &&
            presetId == other.presetId &&
            launchState == other.launchState &&
            createdAt == other.createdAt &&
            updatedAt == other.updatedAt &&
            pinned == other.pinned &&
            sortOrder == other.sortOrder &&
            continueOverrides == other.continueOverrides;
  }

  @override
  int get hashCode => Object.hashAll([
    sessionId,
    workspaceId,
    Object.hashAll(folders),
    Object.hashAll(memberTargets.entries),
    display,
    profileId,
    cli,
    provider,
    model,
    effort,
    presetId,
    launchState,
    createdAt,
    updatedAt,
    pinned,
    sortOrder,
    continueOverrides,
  ]);
}
