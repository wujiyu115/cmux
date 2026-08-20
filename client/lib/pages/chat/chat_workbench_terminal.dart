import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../repositories/session_repository.dart';
import '../../services/terminal/terminal_clipboard_image_paste.dart';
import '../../services/terminal/terminal_session.dart';
import '../../services/terminal/terminal_uri_opener.dart';
import '../../services/workbench/workbench_editor_opener.dart';
import '../../services/workspace_dnd/terminal_drop_ingestor.dart';
import '../../services/workspace_dnd/workspace_drop_target.dart';
import '../../widgets/terminal/parked_send_overlay.dart';
import '../../widgets/terminal/teampilot_alacritty_terminal.dart';
import '../../services/commands/reconciled_keyboard.dart';
import '../../widgets/terminal/terminal_mirror_takeover_scope.dart';
import '../../widgets/terminal_find_bar.dart';
import '../../widgets/workspace_dnd/external_file_drop_region.dart';
import '../../widgets/workspace_dnd/workspace_file_drop_region.dart';
import '../home_workspace/workspace/workspace_session_actions.dart';
import 'chat_workbench_context_menu.dart';

class ChatWorkbenchRunningTerminal extends StatefulWidget {
  const ChatWorkbenchRunningTerminal({
    required this.session,
    required this.terminalTheme,
    required this.terminalController,
    required this.findVisible,
    required this.onFindVisibleChanged,
    required this.onControllerSearchChanged,
    required this.onOpenLink,
    required this.onDisconnect,
    required this.onRestart,
    this.autofocus = true,
    super.key,
  });

  final TerminalSession session;
  final TerminalTheme terminalTheme;
  final TerminalController terminalController;
  final bool findVisible;
  final ValueChanged<bool> onFindVisibleChanged;
  final VoidCallback onControllerSearchChanged;
  final Future<void> Function(String uri) onOpenLink;
  final VoidCallback onDisconnect;
  final Future<void> Function() onRestart;
  final bool autofocus;

  @override
  State<ChatWorkbenchRunningTerminal> createState() =>
      _ChatWorkbenchRunningTerminalState();
}

class _ChatWorkbenchRunningTerminalState
    extends State<ChatWorkbenchRunningTerminal> {
  final ValueNotifier<bool> _menuOpen = ValueNotifier(false);
  final GlobalKey<TerminalViewState> _terminalViewKey =
      GlobalKey<TerminalViewState>();

  @override
  void dispose() {
    _menuOpen.dispose();
    super.dispose();
  }

  /// Fresh per-build ingestor for a drop region — stateless, captures the
  /// session's current namespace + CLI paste behavior.
  TerminalDropIngestor _dropIngestor() => TerminalDropIngestor(
    sink: widget.session.input,
    target: widget.session.runtimeTarget,
    behavior: widget.session.pathDropBehavior,
  );

  void _showDropOutcome(BuildContext context, DropOutcome outcome) {
    if (outcome.anyRejected && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.terminalDropCrossMachineRejected)),
      );
    }
  }

  Future<void> _showContextMenu(
    BuildContext context,
    TapDownDetails details,
    CellOffset? offset,
  ) async {
    _menuOpen.value = true;
    try {
      await showChatWorkbenchTerminalContextMenu(
        context: context,
        menuContext: context,
        terminalController: widget.terminalController,
        globalPosition: details.globalPosition,
        engine: widget.session.engine,
        cellOffset: offset,
        sessionRunning: widget.session.isRunning,
        onFindRequested: () => widget.onFindVisibleChanged(true),
        onOpenLink: widget.onOpenLink,
        onExportScrollback: () => exportChatWorkbenchTerminalScrollback(
          context,
          widget.session.engine,
        ),
        onDisconnect: widget.onDisconnect,
        onRestart: widget.onRestart,
      );
    } finally {
      if (mounted) _menuOpen.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return TerminalFindShortcuts(
      findVisible: widget.findVisible,
      onToggleFind: () => widget.onFindVisibleChanged(true),
      onFindNext: () {
        widget.terminalController.searchNext();
        widget.onControllerSearchChanged();
      },
      onFindPrevious: () {
        widget.terminalController.searchPrev();
        widget.onControllerSearchChanged();
      },
      onCloseFind: () {
        widget.terminalController.searchClear();
        widget.onFindVisibleChanged(false);
      },
      child: Stack(
        children: [
            TerminalMirrorTakeoverScope(
              session: widget.session,
              terminalViewKey: _terminalViewKey,
              builder: (readOnly) => ExternalFileDropRegion(
              target: _dropIngestor(),
              onOutcome: (outcome) => _showDropOutcome(context, outcome),
              child: WorkspaceFileDropRegion(
                target: _dropIngestor(),
                onOutcome: (outcome) => _showDropOutcome(context, outcome),
                child: TeampilotAlacrittyTerminal(
                  engine: widget.session.engine,
                  controller: widget.terminalController,
                  theme: widget.terminalTheme,
                  terminalViewKey: _terminalViewKey,
                  readOnly: readOnly,
                  onPaste: () => TerminalClipboardImagePaste().paste(
                    engine: widget.session.engine,
                    controller: widget.terminalController,
                    sink: widget.session.input,
                    target: widget.session.runtimeTarget,
                    behavior: widget.session.pathDropBehavior,
                  ),
                  // Chat workbench keeps the wider inset (dock shell uses 8).
                  padding: const EdgeInsets.symmetric(
                    horizontal: 36,
                    vertical: 16,
                  ),
                  autofocus:
                      widget.autofocus && !widget.findVisible && !readOnly,
                  linkProviders: widget.session.linkProviders,
                  onPtyResize: widget.session.onTerminalPtyResize,
                  onTapDown: (_, offset) {
                    final keyboard = ReconciledKeyboard.instance.state;
                    if (!keyboard.isControlPressed &&
                        !keyboard.isMetaPressed) {
                      widget.terminalController.clearSelection();
                    }
                  },
                  onLinkActivate: (uri) {
                    unawaited(widget.onOpenLink(uri));
                  },
                  onSecondaryTapDown: (details, offset) {
                    unawaited(_showContextMenu(context, details, offset));
                  },
                ),
              ),
            ),
            ),
            if (widget.findVisible)
              Positioned(
                left: 8,
                right: 8,
                top: 8,
                child: TerminalFindBar(
                  engine: widget.session.engine,
                  controller: widget.terminalController,
                  searchLabel: context.l10n.terminalFind,
                  noResultsLabel: context.l10n.terminalFindNoResults,
                  onClose: () {
                    widget.terminalController.searchClear();
                    widget.onFindVisibleChanged(false);
                  },
                ),
              ),
            ParkedSendOverlay(
              submissions: widget.session.parkedUserSubmissions,
              isUnread: widget.session.isUnreadParkedMessage,
            ),
          ],
        ),
    );
  }
}

Future<void> openChatWorkbenchTerminalLink({
  required String link,
  required ChatCubit chatCubit,
  required WorkbenchEditorOpener editorOpener,
  required String workspaceId,
  required bool Function() isMounted,
}) async {
  await TerminalUriOpener.open(
    link,
    workingDirectory: chatCubit.activeTabWorkingDirectory,
    openInEditor: (path) async {
      if (!isMounted()) return;
      await editorOpener.openFile(workspaceId, path);
    },
  );
}

void consumeChatWorkbenchRouteSession({
  required String? routeSessionId,
  required bool handledRouteSession,
  required ChatState state,
  required ChatCubit chatCubit,
  required SessionRepository sessionRepo,
  required AppLocalizations l10n,
  required void Function(bool handled) onHandled,
  bool connectImmediately = false,
}) {
  if (routeSessionId == null || handledRouteSession) return;

  AppSession? session;
  for (final s in state.sessions) {
    if (s.sessionId == routeSessionId) {
      session = s;
      break;
    }
  }
  if (session == null) return;

  onHandled(true);

  if (chatCubit.tabStore.openTabBySessionId(routeSessionId) != null) {
    return;
  }

  unawaited(
    chatCubit.requestOpenSession(
      buildOpenExistingSessionRequest(
        session: session,
        repo: sessionRepo,
        emptyDisplayTitleFallback: l10n.defaultNewChatSessionTitle,
        connectImmediately: connectImmediately,
      ),
    ),
  );
}

/// Stable key for the chat workbench terminal stack.
///
/// Kept independent of loading/running so the [TerminalView] element is not
/// remounted when connect finishes — only visibility toggles via [Offstage].
const Key kChatWorkbenchTerminalStackKey = ValueKey('chat-terminal-running');

/// Legacy helper for tests that still key off loading vs running transitions.
Key chatWorkbenchTerminalViewKey({
  required bool loading,
  required bool running,
}) {
  if (loading) return const ValueKey('chat-terminal-loading');
  if (running) return const ValueKey('chat-terminal-running');
  return const ValueKey('chat-terminal-placeholder');
}

TerminalController bindChatWorkbenchTerminalController(
  TerminalController current,
  TerminalEngine engine,
) {
  if (identical(current.engine, engine)) return current;
  if (current.engine != null) {
    current.dispose();
    current = TerminalController();
  }
  current.attach(engine);
  return current;
}
