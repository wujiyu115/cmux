import '../../../models/simple_launch_identity.dart';
import '../../../models/session_continue_overrides.dart';
import '../../../models/cli_tool.dart';

/// Disk-write parameters for a session that is already surfaced in the UI.
class SessionPersistParams {
  const SessionPersistParams({
    this.cli,
    this.simpleIdentity,
    this.workingDirectory,
    this.continueOverrides,
  });

  final CliTool? cli;

  /// Simple launch: denormalized identity written to [AppSession].
  final SimpleLaunchIdentity? simpleIdentity;
  final String? workingDirectory;
  final SessionContinueOverrides? continueOverrides;
}
