import 'dart:async';

import '../terminal/terminal_session.dart';

/// Which registry a mirrored session came from. Chat tabs and workspace terminal
/// panes are two disjoint registries; the catalog unifies them under one id space.
enum PairedSessionKind { chat, workspace }

/// Registry-neutral descriptor of one mirrorable terminal, safe to send over the
/// wire. Carries a stable [catalogId] plus display metadata; the live
/// [TerminalSession] is reached via [SessionCatalog.resolve], never serialized.
class PairedSessionRef {
  const PairedSessionRef({
    required this.catalogId,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.sessionId,
    this.memberId,
    this.paneId,
  });

  final String catalogId;
  final PairedSessionKind kind;
  final String title;
  final String subtitle;

  /// Chat: `AppSession.sessionId`. Workspace: the owning group/workspace id.
  final String sessionId;

  /// Chat member-shell key (null for a chat tab's main shell).
  final String? memberId;

  /// Workspace terminal pane id (null for chat).
  final String? paneId;

  /// Stable synthetic key: same live session yields the same id across reloads.
  static String chatId(String sessionId, String? memberId) =>
      'chat:$sessionId:${memberId ?? 'main'}';

  static String workspaceId(String paneId) => 'ws:$paneId';
}

/// One catalog entry: its wire descriptor plus the live session behind it.
class SessionCatalogEntry {
  const SessionCatalogEntry(this.ref, this.session);
  final PairedSessionRef ref;
  final TerminalSession session;
}

/// Produces the current entries of one registry. Injected from bootstrap so the
/// catalog stays ignorant of cubit internals (chat store / workspace registry).
typedef SessionCatalogSource = List<SessionCatalogEntry> Function();

/// Read-only union of every mirrorable terminal across the app's disjoint
/// session registries. Sources are registered at bootstrap; [list] flattens them
/// on demand and [resolve] maps a wire [PairedSessionRef.catalogId] back to a
/// live [TerminalSession]. Emits on [changes] when a registry signals churn.
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
