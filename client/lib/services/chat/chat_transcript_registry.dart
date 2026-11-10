import 'dart:async';

import 'chat_transcript_session.dart';

/// The live transcript behind each chat pane.
///
/// The *mode* is not here: it is a launch option carried by the pane itself
/// (`WorkspaceTerminalEntry.mode`), because a chat pane starts an agent and a
/// terminal pane does not. This registry only holds the readers, keyed by pane,
/// for panes that have one — created on first paint and dropped when the pane
/// goes away.
///
/// The paired phone reads the same readers, so the mirror never needs a second
/// source of truth about what a pane is.
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
