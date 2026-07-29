import '../../cubits/chat/model/session_connect_request.dart';
import '../../cubits/chat/model/session_create_request.dart';
import '../../cubits/chat/model/session_open_request.dart';
import '../../repositories/session_repository.dart';

/// User- or system-initiated launch operation routed through
/// [SessionLaunchPipeline].
sealed class LaunchOperation {}

/// Surface a persisted session in the workbench and optionally connect.
final class OpenSessionOperation extends LaunchOperation {
  OpenSessionOperation(this.request);

  final SessionOpenRequest request;
}

/// Stage a new conversation tab immediately, then persist and connect async.
final class CreateSessionOperation extends LaunchOperation {
  CreateSessionOperation(this.request);

  final SessionCreateRequest request;
}

/// Connect the active workspace session (materialize when tabs are empty).
final class ConnectWorkspaceOperation extends LaunchOperation {
  ConnectWorkspaceOperation(this.request, {this.repo});

  final SessionConnectRequest request;
  final SessionRepository? repo;
}

/// Disconnect then reconnect the active workspace session.
final class RestartWorkspaceOperation extends LaunchOperation {
  RestartWorkspaceOperation(this.request, {this.repo});

  final SessionConnectRequest request;
  final SessionRepository? repo;
}
