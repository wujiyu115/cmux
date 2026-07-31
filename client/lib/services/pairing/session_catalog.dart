import 'dart:async';

import '../terminal/terminal_session.dart';

/// Descriptor of one mirrorable terminal, safe to send over the wire. Carries a
/// stable [catalogId] plus display metadata; the live [TerminalSession] is
/// reached via [SessionCatalog.resolve], never serialized.
class PairedSessionRef {
  const PairedSessionRef({
    required this.catalogId,
    required this.title,
    required this.subtitle,
    required this.workspaceId,
    required this.paneId,
  });

  final String catalogId;
  final String title;
  final String subtitle;

  /// Workspace this pane belongs to, so `workspace.list` can group it.
  final String workspaceId;

  /// Workspace terminal pane id.
  final String paneId;

  /// Stable synthetic key: the same live pane yields the same id across reloads.
  static String paneCatalogId(String paneId) => 'ws:$paneId';
}

/// One catalog entry: its wire descriptor plus the live session behind it.
class SessionCatalogEntry {
  const SessionCatalogEntry(this.ref, this.session);
  final PairedSessionRef ref;
  final TerminalSession session;
}

/// Produces the current entries of one registry. Injected from bootstrap so the
/// catalog stays ignorant of the workspace terminal registry's internals.
typedef SessionCatalogSource = List<SessionCatalogEntry> Function();

/// Read-only view of every mirrorable terminal. Sources are registered at
/// bootstrap; [list] flattens them on demand and [resolve] maps a wire
/// [PairedSessionRef.catalogId] back to a live [TerminalSession]. Emits on
/// [changes] when a registry signals churn.
class SessionCatalog {
  SessionCatalog();

  final _sources = <SessionCatalogSource>[];
  final _changes = StreamController<void>.broadcast();

  void addSource(SessionCatalogSource source) => _sources.add(source);

  /// Fires whenever a registry gains/loses sessions so the host can push a fresh
  /// `session.list` to subscribed clients.
  Stream<void> get changes => _changes.stream;

  void notifyChanged() {
    if (!_changes.isClosed) _changes.add(null);
  }

  List<SessionCatalogEntry> list() => [
    for (final source in _sources) ...source(),
  ];

  SessionCatalogEntry? resolve(String catalogId) {
    for (final entry in list()) {
      if (entry.ref.catalogId == catalogId) return entry;
    }
    return null;
  }

  void dispose() {
    _sources.clear();
    unawaited(_changes.close());
  }
}
