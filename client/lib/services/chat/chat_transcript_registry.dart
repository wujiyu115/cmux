import 'dart:async';

import 'chat_transcript_session.dart';

/// Which panes are currently showing chat instead of the terminal, and the live
/// transcript behind each one.
///
/// A pane's mode is a view choice, not a launch option: the agent runs in the
/// same PTY either way, so switching never restarts it. That is why the mode
/// lives here (per live pane) rather than in the persisted session model — a
/// reopened pane starts in the terminal and the user picks again.
///
/// The paired phone reads the same registry: a pane listed in chat mode is
/// rendered as a transcript there, which is how "the mode the tab was opened in"
/// reaches the mirror without a second source of truth.
class ChatTranscriptRegistry {
  ChatTranscriptRegistry();

  final _byPane = <String, ChatTranscriptSession>{};
  final _changes = StreamController<void>.broadcast();

  /// Fires when a pane enters or leaves chat mode, so hosts can re-publish the
  /// session list to paired clients.
  Stream<void> get changes => _changes.stream;

  /// Live transcript registered for [paneId], or null when the pane shows the
  /// terminal.
  ChatTranscriptSession? operator [](String paneId) => _byPane[paneId];

  /// True when [paneId] renders as chat (`session.list` reports this as the
  /// pane's mode).
  bool isChatMode(String paneId) => _byPane.containsKey(paneId);

  /// Panes currently in chat mode.
  Iterable<String> get chatPaneIds => _byPane.keys;

  /// Adds [session] for [paneId], replacing (and disposing) a previous one.
  /// The caller owns [session]'s lifecycle up to this point.
  void register(String paneId, ChatTranscriptSession session) {
    final previous = _byPane[paneId];
    _byPane[paneId] = session;
    if (previous != null && !identical(previous, session)) previous.dispose();
    _notify();
  }

  /// Drops [paneId] from chat mode. The session is disposed unless
  /// [dispose] is false (a caller that keeps it for another pane).
  void unregister(String paneId, {bool dispose = true}) {
    final session = _byPane.remove(paneId);
    if (session == null) return;
    if (dispose) session.dispose();
    _notify();
  }

  /// Drops panes that no longer exist in their group, so a closed pane's poll
  /// stops with it.
  void prune(Set<String> livePaneIds) {
    final stale = [
      for (final paneId in _byPane.keys)
        if (!livePaneIds.contains(paneId)) paneId,
    ];
    for (final paneId in stale) {
      unregister(paneId);
    }
  }

  void dispose() {
    for (final session in _byPane.values) {
      session.dispose();
    }
    _byPane.clear();
    unawaited(_changes.close());
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }
}
