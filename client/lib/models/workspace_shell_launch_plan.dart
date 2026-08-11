import 'package:flutter/foundation.dart';

import 'runtime_target.dart';

/// Resolved argv/cwd for [TerminalSession.connectWorkspaceShell].
@immutable
class WorkspaceShellLaunchPlan {
  const WorkspaceShellLaunchPlan({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.useWslPaths,
    required this.inheritHostEnvironment,
    required this.runtimeTarget,
    required this.usesRemoteTransport,
    this.environment = const {},
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final bool useWslPaths;
  final bool inheritHostEnvironment;
  final RuntimeTarget runtimeTarget;
  final bool usesRemoteTransport;

  /// Extra env stamped onto the spawned process, merged over the inherited host
  /// environment. Carries the agent-status seat identity the shared Claude hook
  /// reads at run time; empty when the pane reports no status (ssh, or gateway
  /// down), in which case the launch env is left exactly as before.
  final Map<String, String> environment;
}
