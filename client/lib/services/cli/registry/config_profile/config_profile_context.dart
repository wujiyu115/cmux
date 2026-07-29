import 'package:path/path.dart' as p;

import '../../../../models/team_config.dart';
import '../../../io/filesystem.dart';
import '../../../host/host_execution_environment.dart';
import '../../../provider/provider_catalog_access.dart';
import '../../../storage/runtime_layout.dart';
import '../../../agent_status/member_agent_status_endpoint.dart';
import 'config_profile_scope.dart';

export 'config_profile_scope.dart';

/// Path facade for [ConfigProfileCapability] implementations.
abstract interface class ConfigProfilePaths {
  String get basePath;

  /// Runtime user home (`native` / `wsl` / `ssh`), used for global CLI state
  /// such as Cursor workspace trust markers under `$HOME/.cursor/projects/`.
  String get home;

  Filesystem get fs;

  p.Context get pathContext;

  RuntimeLayout get layout;

  String sessionToolDir(
    String workspaceId,
    String sessionId,
    String tool, {
    String? memberId,
  });
}

/// Shared profile I/O, extension settings hooks, and team-lead scripts.
abstract interface class ConfigProfileDelegate implements ConfigProfilePaths {
  Future<Map<String, Object?>> readMetadataFile(
    String path,
    Map<String, Object?> defaults,
  );

  Future<void> writeJsonIfChanged(String path, Map<String, Object?> value);

  Future<Map<String, Object?>> metadataWithTrustedProjects({
    required String metadataPath,
    required Map<String, Object?> defaultMetadata,
    required Map<String, Object?> defaultProjectConfig,
    required Iterable<String> directories,
  });

  Future<bool> trustedProjectsAlreadyCurrent(
    String metadataPath,
    Iterable<String> directories, {
    required Map<String, Object?> defaultMetadata,
  });

  Future<Map<String, Object?>> readSettingsFile(String path);

  Future<void> writeSettingsFile(
    String path,
    Map<String, Object?> settings, {
    String? memberToolDir,
    required String tool,
    String? teamId,
    String? workspaceId,
  });

  Future<bool> hasEnabledExtensionSettingsHooks(
    String tool, {
    String? teamId,
    String? workspaceId,
  });

  Future<Map<String, Object?>> applyExtensionSettings(
    Map<String, Object?> settings,
    String? memberToolDir, {
    required String tool,
    String? teamId,
    String? workspaceId,
  });

  Future<Map<String, Object?>> maybeApplyTeamLeadHooks(
    Map<String, Object?> settings,
    TeamMemberConfig member,
    String memberToolDir, {
    required bool forceTeamLeadDelegateMode,
  });

  Future<String?> resolveAppendSystemPromptPath({
    required LaunchProfileScope scope,
    required String tool,
    required TeamMemberConfig member,
  });

  HostExecutionEnvironment hostEnvironmentForProvision();
}

class ConfigProfileSessionContext {
  const ConfigProfileSessionContext({
    required this.workspaceId,
    required this.teamId,
    required this.sessionId,
    required this.members,
    required this.paths,
    this.team,
    this.memberId,
  });

  final String workspaceId;
  final String teamId;
  final String sessionId;
  final List<TeamMemberConfig> members;
  final ConfigProfileDelegate paths;
  final TeamProfile? team;
  final String? memberId;
}

class ConfigProfileLaunchContext {
  const ConfigProfileLaunchContext({
    required this.workspaceId,
    required this.teamId,
    required this.sessionId,
    required this.scope,
    this.team,
    this.member,
    required this.members,
    this.workingDirectory = '',
    this.additionalDirectories = const [],
    required this.paths,
    required this.catalog,
    this.leadSessionId,
    this.agentStatus,
    this.memberId,
  });

  final String workspaceId;
  final String teamId;
  final String sessionId;
  final LaunchProfileScope scope;
  final TeamProfile? team;
  final TeamMemberConfig? member;
  final List<TeamMemberConfig> members;
  final String? workingDirectory;
  final List<String> additionalDirectories;

  /// Work-plane delegate: session runtime trees, settings writes, hooks.
  final ConfigProfileDelegate paths;

  /// Control-plane paths: provider catalog and home credential reads.
  final ConfigProfilePaths catalog;
  final String? leadSessionId;

  /// Permission / status HTTP hooks (`POST /agent-status`). Stamped at
  /// lifecycle (Task 7); null until then — writers install only when set.
  final MemberAgentStatusEndpoint? agentStatus;
  final String? memberId;

  bool get crossMachine => configProfileCrossMachine(catalog, paths);

  /// True when launching Simple (unteamed). Team launches always pass a
  /// non-empty [teamId] even when the [TeamProfile] object is omitted.
  bool get isSimple => teamId.trim().isEmpty;
}
