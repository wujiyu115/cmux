import 'session_catalog.dart';

/// The kind of thing a client asked the host to activate: resume a persisted
/// chat [AppSession], or open/reuse a workspace terminal pane.
enum PairingActivationKind { chat, workspace }

/// One persisted chat [AppSession] under a workspace, as advertised by
/// `workspace.list`. This is a *disk* record — [started] reflects launch state,
/// not liveness; whether it is currently mirrorable is decided by matching its
/// synthetic [PairedSessionRef.chatId] against the live [SessionCatalog].
class PairingPersistedSession {
  const PairingPersistedSession({
    required this.sessionId,
    required this.title,
    required this.subtitle,
    this.cli,
    this.started = false,
  });

  final String sessionId;
  final String title;
  final String subtitle;

  /// CLI-tool label, if any (metadata only).
  final String? cli;

  /// AppSession.launchState == started (NOT liveness).
  final bool started;
}

/// One workspace and its persisted sessions, produced host-side by enumerating
/// the on-disk workspace index. Live panes are *not* carried here — the handler
/// merges those from the [SessionCatalog] at `workspace.list` time.
class PairingWorkspaceInfo {
  const PairingWorkspaceInfo({
    required this.workspaceId,
    required this.title,
    this.sessions = const [],
  });

  final String workspaceId;
  final String title;
  final List<PairingPersistedSession> sessions;
}

/// A client's request to activate a specific session/pane so it becomes live and
/// mirrorable. [kind] selects which host resume path runs; the id fields are
/// interpreted per kind (chat → [sessionId]/[memberId]; workspace → [paneId]).
class PairingActivationRequest {
  const PairingActivationRequest({
    required this.workspaceId,
    required this.kind,
    this.sessionId,
    this.memberId,
    this.paneId,
  });

  final String workspaceId;
  final PairingActivationKind kind;
  final String? sessionId;
  final String? memberId;
  final String? paneId;
}

/// Outcome of a host-side activation: the [catalogId] the client should then
/// `terminal.subscribe` to. [fallback] is true when a chat resume could not be
/// honoured and the host opened a plain workspace terminal instead.
class PairingActivationResult {
  const PairingActivationResult({required this.catalogId, this.fallback = false});

  final String catalogId;
  final bool fallback;
}

/// Enumerates every workspace (and its persisted sessions) from disk. Injected
/// from bootstrap so the pairing stack stays ignorant of the session repository.
typedef PairingWorkspaceIndexProvider =
    Future<List<PairingWorkspaceInfo>> Function();

/// Activates a session/pane host-side and returns the resulting catalog id once
/// it is (or is about to become) live. Returns null when activation fails and no
/// fallback was possible. Injected from bootstrap.
typedef PairingSessionActivator =
    Future<PairingActivationResult?> Function(PairingActivationRequest);
