import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../utils/ui/app_keys.dart';
import '../../cubits/chat/session_launch_retry.dart';
import 'package:shared_ui/shared_ui.dart';

/// Tab-bar control to switch a session between Chat and Terminal.
class SessionWorkbenchViewToggle extends StatelessWidget {
  const SessionWorkbenchViewToggle({
    required this.workspaceId,
    required this.tabScopeId,
    super.key,
  });

  final String workspaceId;
  final String tabScopeId;

  @override
  Widget build(BuildContext context) {
    final active = context.select<WorkbenchCubit, WorkbenchTabId?>(
      (c) => c.activeTabId(workspaceId),
    );
    if (active == null || active.kind != WorkbenchTabKind.session) {
      return const SizedBox.shrink();
    }
    final sessionId = active.id;
    final view = context.select<ChatCubit, SessionWorkbenchView>((c) {
      final tab = c.tabStore.openTabBySessionId(sessionId);
      return tab?.workbenchView ?? SessionWorkbenchView.chat;
    });
    final showingChat = view == SessionWorkbenchView.chat;
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return TpIconButton(
      key: AppKeys.sessionWorkbenchViewToggle,
      icon: showingChat
          ? Icons.terminal_rounded
          : Icons.chat_bubble_outline_rounded,
      tooltip: showingChat
          ? l10n.sessionWorkbenchShowTerminal
          : l10n.sessionWorkbenchShowChat,
      color: cs.onSurfaceVariant,
      onTap: () => unawaited(
        _toggle(context, sessionId: sessionId, showingChat: showingChat),
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context, {
    required String sessionId,
    required bool showingChat,
  }) async {
    final chat = context.read<ChatCubit>();
    final workbench = context.read<WorkbenchCubit>();
    final tabId = WorkbenchTabId.session(sessionId);

    if (showingChat) {
      chat.setSessionWorkbenchView(sessionId, SessionWorkbenchView.terminal);
      workbench.pinTab(workspaceId, tabId);
      workbench.ensureTab(workspaceId, tabId, preview: false);

      final tab = chat.tabStore.openTabBySessionId(sessionId);
      if (tab == null || tab.isRunning) return;
      if (!context.mounted) return;

      final session = _resolveSession(chat, sessionId);
      if (session == null) return;

      await chat.connectWorkspaceSession(
        buildRetryExistingSessionConnect(
          session: session,
          preserveWorkbenchView: false,
        ),
      );
      return;
    }

    chat.setSessionWorkbenchView(sessionId, SessionWorkbenchView.chat);
  }

  AppSession? _resolveSession(ChatCubit chat, String sessionId) {
    for (final s in chat.state.sessions) {
      if (s.sessionId == sessionId) return s;
    }
    return chat.tabStore.openTabBySessionId(sessionId)?.persistedSession;
  }
}
