/// Wire shape of one agent-attention notice forwarded from the desktop host to
/// a paired phone (`agent.notice`, an unsolicited host→client JSON frame).
///
/// Deliberately free of Flutter imports and of any `services/notification/`
/// dependency: both the host and the phone import this file, and pulling the
/// notification layer in here would invert the layering (pairing → notification
/// → router/bloc). The host maps its own `AgentNoticeKind` onto [kind] by name.
///
/// Only structured fields travel — the phone renders the copy with its own
/// `context.l10n`, so a zh phone paired to an en desktop reads Chinese.
library;

enum PairingAgentNoticeKind { done, interrupted, waiting }

class PairingAgentNotice {
  const PairingAgentNotice({
    required this.kind,
    required this.seatId,
    this.catalogId,
    this.workspaceId = '',
    this.workspaceLabel = '',
    this.title = '',
    this.atMs = 0,
  });

  final PairingAgentNoticeKind kind;

  /// Host seat id: `ws:<paneId>` for a workspace terminal pane, or an
  /// `AppSession.sessionId` for a chat session tab.
  final String seatId;

  /// Pairing catalog id, set only when the host can actually mirror this seat.
  /// Null for chat session tabs (never in the catalog) and for panes whose PTY
  /// has already exited — the phone then notifies without offering navigation.
  final String? catalogId;

  final String workspaceId;
  final String workspaceLabel;

  /// Session/pane display name. Empty when the host could not attribute the
  /// seat; the phone falls back to the localized kind title.
  final String title;

  /// Epoch millis (UTC) of the attention edge, from the seat's `updatedAt`.
  final int atMs;

  bool get isMirrorable => (catalogId ?? '').isNotEmpty;

  PairingAgentNotice withCatalogId(String? id) => PairingAgentNotice(
    kind: kind,
    seatId: seatId,
    catalogId: id,
    workspaceId: workspaceId,
    workspaceLabel: workspaceLabel,
    title: title,
    atMs: atMs,
  );

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'seatId': seatId,
    if (catalogId != null) 'catalogId': catalogId,
    'workspaceId': workspaceId,
    'workspaceLabel': workspaceLabel,
    'title': title,
    'atMs': atMs,
  };

  /// Returns null when the payload is unusable — notably an unknown [kind], so a
  /// newer desktop that adds a kind cannot crash an older phone.
  static PairingAgentNotice? tryFromJson(Map<String, Object?> json) {
    final kindName = _string(json['kind']);
    PairingAgentNoticeKind? kind;
    for (final candidate in PairingAgentNoticeKind.values) {
      if (candidate.name == kindName) kind = candidate;
    }
    if (kind == null) return null;
    final seatId = _string(json['seatId']);
    if (seatId.isEmpty) return null;
    final catalogId = _string(json['catalogId']);
    return PairingAgentNotice(
      kind: kind,
      seatId: seatId,
      catalogId: catalogId.isEmpty ? null : catalogId,
      workspaceId: _string(json['workspaceId']),
      workspaceLabel: _string(json['workspaceLabel']),
      title: _string(json['title']),
      atMs: switch (json['atMs']) {
        final int v => v,
        final num v => v.toInt(),
        _ => 0,
      },
    );
  }

  static String _string(Object? value) => value is String ? value.trim() : '';
}
