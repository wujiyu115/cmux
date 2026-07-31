import 'session_catalog.dart';

/// One workspace as advertised by `workspace.list`, produced host-side by
/// enumerating the on-disk workspace index. Its live terminal panes are *not*
/// carried here — the handler merges those from the [SessionCatalog] at
/// `workspace.list` time, so a workspace with nothing running still lists.
class PairingWorkspaceInfo {
  const PairingWorkspaceInfo({required this.workspaceId, required this.title});

  final String workspaceId;
  final String title;
}

/// A client's request for a mirrorable terminal in [workspaceId]. [paneId] names
/// a specific pane the phone saw; when it is null or no longer alive the host
/// opens the workspace's default terminal instead.
class PairingActivationRequest {
  const PairingActivationRequest({required this.workspaceId, this.paneId});

  final String workspaceId;
  final String? paneId;
}

/// Outcome of a host-side activation: the [catalogId] the client should then
/// `terminal.subscribe` to. [fallback] is true when the requested pane was gone
/// and the host opened a fresh terminal instead.
class PairingActivationResult {
  const PairingActivationResult({required this.catalogId, this.fallback = false});

  final String catalogId;
  final bool fallback;
}

/// Enumerates every workspace from disk. Injected from bootstrap so the pairing
/// stack stays ignorant of the session repository.
typedef PairingWorkspaceIndexProvider =
    Future<List<PairingWorkspaceInfo>> Function();

/// Opens/reuses a terminal host-side and returns the resulting catalog id once it
/// is (or is about to become) live. Returns null when nothing could be opened.
/// Injected from bootstrap.
typedef PairingSessionActivator =
    Future<PairingActivationResult?> Function(PairingActivationRequest);
