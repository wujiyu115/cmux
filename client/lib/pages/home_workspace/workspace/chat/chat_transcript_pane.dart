import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../l10n/l10n_extensions.dart';
import '../../../../services/chat/chat_transcript_row.dart';
import 'chat_transcript_type.dart';

/// Chat view over a pane that keeps running its agent in the terminal.
///
/// Rows come from the CLI's own session store, so nothing here talks to the
/// agent: the composer writes to the same PTY the terminal view writes to, and
/// the transcript is re-read from disk. That is what makes the two views
/// interchangeable mid-turn instead of two kinds of session.
class ChatTranscriptPane extends StatefulWidget {
  const ChatTranscriptPane({
    required this.transcript,
    required this.onSend,
    required this.canSend,
    this.agentStarting = false,
    this.background,
    this.foreground,
    this.composerFocusNode,
    super.key,
  });

  /// Live rows plus the reason a pane has none.
  final ValueListenable<ChatTranscriptSnapshot> transcript;

  /// Sends one prompt to the pane's PTY (the caller appends the newline).
  final ValueChanged<String> onSend;

  /// False while the PTY cannot take input (connecting, exited).
  final bool canSend;

  /// True while this pane's agent has been started but has not written a
  /// session yet (the first few seconds, or before its first message). The
  /// prompt still has somewhere to land, so the composer stays usable.
  final bool agentStarting;

  final Color? background;
  final Color? foreground;
  final FocusNode? composerFocusNode;

  @override
  State<ChatTranscriptPane> createState() => _ChatTranscriptPaneState();
}

class _ChatTranscriptPaneState extends State<ChatTranscriptPane> {
  final _scroll = ScrollController();
  final _composer = TextEditingController();
  final _expanded = <String>{};

  /// A prompt that never showed up in the store — the pane's agent may not be
  /// running, or it may be a different session than the one being read.
  bool _undelivered = false;
  Timer? _deliveryCheck;

  @override
  void initState() {
    super.initState();
    widget.transcript.addListener(_onTranscriptChanged);
  }

  @override
  void didUpdateWidget(ChatTranscriptPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transcript != widget.transcript) {
      oldWidget.transcript.removeListener(_onTranscriptChanged);
      widget.transcript.addListener(_onTranscriptChanged);
    }
  }

  @override
  void dispose() {
    _deliveryCheck?.cancel();
    widget.transcript.removeListener(_onTranscriptChanged);
    _scroll.dispose();
    _composer.dispose();
    super.dispose();
  }

  /// Follows new rows only when the reader is already at the bottom, so a
  /// scroll-back is never yanked away by the next poll.
  void _onTranscriptChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final atBottom = position.maxScrollExtent - position.pixels < 120;
      if (!atBottom) return;
      _scroll.jumpTo(position.maxScrollExtent);
    });
  }

  void _send() {
    final text = _composer.text.trim();
    if (text.isEmpty || !_canType(widget.transcript.value)) return;
    final promptsBefore = _promptCount();
    _composer.clear();
    setState(() => _undelivered = false);
    widget.onSend(text);
    _checkDelivery(text, promptsBefore);
  }

  /// The store is the only proof a prompt reached the agent: the CLI writes the
  /// user record as it receives it. If nothing new shows up, say so and hand the
  /// text back instead of letting it disappear.
  void _checkDelivery(String text, int promptsBefore) {
    _deliveryCheck?.cancel();
    _deliveryCheck = Timer(const Duration(seconds: 5), () {
      if (!mounted || _promptCount() > promptsBefore) return;
      setState(() {
        _undelivered = true;
        if (_composer.text.isEmpty) _composer.text = text;
      });
    });
  }

  int _promptCount() => widget.transcript.value.rows
      .where((row) => row.kind == ChatTranscriptRowKind.user)
      .length;

  /// Composing needs a live PTY *and* a session store to read the answer back
  /// from. Without one the prompt would land in a bare shell and vanish — no
  /// bubble, no error — so the composer states why instead.
  bool _canType(ChatTranscriptSnapshot snapshot) {
    if (!widget.canSend) return false;
    // A chat pane started its own agent: the session file may simply not
    // exist yet, but the PTY is right there and will take the prompt.
    if (widget.agentStarting) return true;
    return switch (snapshot.unavailable) {
      ChatTranscriptUnavailable.noDirectory ||
      ChatTranscriptUnavailable.noSessionFile ||
      ChatTranscriptUnavailable.unsupportedFamily => false,
      // A failed read is a snapshot problem, not proof the agent is gone.
      ChatTranscriptUnavailable.readFailed || null => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final foreground =
        widget.foreground ?? Theme.of(context).colorScheme.onSurface;
    return ColoredBox(
      color: widget.background ?? Colors.transparent,
      child: ValueListenableBuilder<ChatTranscriptSnapshot>(
        valueListenable: widget.transcript,
        builder: (context, snapshot, _) {
          return Column(
            children: [
              Expanded(child: _buildBody(context, snapshot, foreground)),
              // Another window's conversation is a real possibility here; say
              // so before the user types into it.
              if (snapshot.borrowed && !_undelivered)
                _buildNotice(
                  context,
                  context.l10n.chatPaneForeignSession,
                  Icons.info_outline,
                ),
              if (_undelivered)
                _buildNotice(
                  context,
                  // A pane that launched its own agent is not looking at another
                  // window's session; more likely its agent is stuck on a
                  // prompt or an error the conversation view cannot show.
                  widget.agentStarting
                      ? context.l10n.chatPanePromptUndeliveredAgent
                      : context.l10n.chatPanePromptUndelivered,
                  Icons.error_outline,
                ),
              TpSeparator(color: foreground.withValues(alpha: 0.12)),
              _buildComposer(context, foreground, snapshot),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ChatTranscriptSnapshot snapshot,
    Color foreground,
  ) {
    final type = ChatTranscriptType.of(context);
    final l10n = context.l10n;
    final unavailable = snapshot.unavailable;
    if (snapshot.rows.isEmpty) {
      final String message = switch (unavailable) {
        null => l10n.chatPaneEmpty,
        ChatTranscriptUnavailable.noDirectory =>
          l10n.chatPaneUnavailableNoDirectory,
        ChatTranscriptUnavailable.noSessionFile when widget.agentStarting =>
          l10n.chatPaneAgentStarting,
        ChatTranscriptUnavailable.noSessionFile =>
          l10n.chatPaneUnavailableNoSession,
        ChatTranscriptUnavailable.unsupportedFamily =>
          l10n.chatPaneUnavailableUnsupported,
        ChatTranscriptUnavailable.readFailed => l10n.chatPaneUnavailableRead,
      };
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: type.bodyIn(foreground.withValues(alpha: 0.6)),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: snapshot.rows.length,
      itemBuilder: (context, index) {
        final row = snapshot.rows[index];
        return Padding(
          key: ValueKey(row.id),
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildRow(context, row, foreground),
        );
      },
    );
  }

  Widget _buildRow(BuildContext context, ChatTranscriptRow row, Color fg) {
    final type = ChatTranscriptType.of(context);
    final l10n = context.l10n;
    switch (row.kind) {
      case ChatTranscriptRowKind.user:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: fg.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(row.text, style: type.bodyIn(fg)),
        );
      case ChatTranscriptRowKind.assistant:
        return SelectableText(row.text, style: type.bodyIn(fg));
      case ChatTranscriptRowKind.thought:
        return _CollapsibleRow(
          label: l10n.chatPaneThoughts,
          body: row.text,
          expanded: _expanded.contains(row.id),
          foreground: fg,
          onToggle: () => _toggle(row.id),
          italic: true,
        );
      case ChatTranscriptRowKind.tool:
        final header = [
          row.toolName,
          if (row.detail.isNotEmpty) row.detail,
        ].join('  ');
        return _ToolRow(
          header: header,
          body: row.text,
          running: row.running,
          expanded: _expanded.contains(row.id),
          foreground: fg,
          onToggle: () => _toggle(row.id),
        );
      case ChatTranscriptRowKind.notice:
        return Center(
          child: Text(
            l10n.chatPaneCompacted,
            style: type.metaIn(fg.withValues(alpha: 0.45)),
          ),
        );
    }
  }

  void _toggle(String id) {
    setState(() {
      if (!_expanded.remove(id)) _expanded.add(id);
    });
  }

  Widget _buildNotice(BuildContext context, String text, IconData icon) {
    final type = ChatTranscriptType.of(context);
    final color = Theme.of(context).colorScheme.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: type.metaIn(color))),
        ],
      ),
    );
  }

  Widget _buildComposer(
    BuildContext context,
    Color foreground,
    ChatTranscriptSnapshot snapshot,
  ) {
    final l10n = context.l10n;
    final type = ChatTranscriptType.of(context);
    final enabled = _canType(snapshot);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _composer,
              focusNode: widget.composerFocusNode,
              enabled: enabled,
              minLines: 1,
              maxLines: 6,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              style: type.bodyIn(foreground),
              decoration: InputDecoration(
                isDense: true,
                hintText: enabled
                    ? l10n.chatPaneComposerHint
                    : l10n.chatPaneComposerNeedsAgent,
                hintStyle: type.bodyIn(foreground.withValues(alpha: 0.4)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: foreground.withValues(alpha: 0.15),
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TpIconButton(
            icon: Icons.arrow_upward,
            tooltip: l10n.chatPaneSend,
            enabled: enabled,
            onTap: _send,
          ),
        ],
      ),
    );
  }
}

class _CollapsibleRow extends StatelessWidget {
  const _CollapsibleRow({
    required this.label,
    required this.body,
    required this.expanded,
    required this.foreground,
    required this.onToggle,
    this.italic = false,
  });

  final String label;
  final String body;
  final bool expanded;
  final Color foreground;
  final VoidCallback onToggle;
  final bool italic;

  @override
  Widget build(BuildContext context) {
    final type = ChatTranscriptType.of(context);
    final dim = foreground.withValues(alpha: 0.55);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Row(
            children: [
              Icon(
                expanded ? Icons.expand_more : Icons.chevron_right,
                size: 16,
                color: dim,
              ),
              Text(label, style: type.metaIn(dim)),
            ],
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: Text(
              body,
              style: type
                  .bodyIn(dim)
                  .copyWith(fontStyle: italic ? FontStyle.italic : null),
            ),
          ),
      ],
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.header,
    required this.body,
    required this.running,
    required this.expanded,
    required this.foreground,
    required this.onToggle,
  });

  final String header;
  final String body;
  final bool running;
  final bool expanded;
  final Color foreground;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final type = ChatTranscriptType.of(context);
    final dim = foreground.withValues(alpha: 0.7);
    return InkWell(
      onTap: body.isEmpty ? null : onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: running
                    ? CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : Icon(
                        body.isEmpty
                            ? Icons.circle_outlined
                            : expanded
                            ? Icons.expand_more
                            : Icons.chevron_right,
                        size: 16,
                        color: dim,
                      ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  header,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.metaIn(dim),
                ),
              ),
            ],
          ),
          if (expanded && body.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 20, top: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: foreground.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                body,
                style: type.toolIn(foreground.withValues(alpha: 0.8)),
              ),
            ),
        ],
      ),
    );
  }
}
