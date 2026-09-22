import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/chat_cubit.dart';
import '../../cubits/editor_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/session/workspace_tab_session_scope.dart';
import '../../widgets/app_toast/app_toast.dart';
import '../workspace_dnd/editor_agent_reference_sender.dart';

/// Desktop/mobile context menu for [CodeEditor] (right-click / long-press).
class FileEditorContextMenuController implements SelectionToolbarController {
  const FileEditorContextMenuController({
    required this.onMenuOpenChanged,
    this.workspaceId,
    this.filePath,
  });

  final ValueChanged<bool> onMenuOpenChanged;

  /// Owning editor pane, when known. Falls back to the active workbench file
  /// tab for editors mounted outside a workspace pane.
  final String? workspaceId;
  final String? filePath;

  @override
  void hide(BuildContext context) {}

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  }) {
    final l10n = context.l10n;
    final editorCubit = context.read<EditorCubit>();
    String? path = filePath;
    String? workspaceId = this.workspaceId;
    if (path == null || workspaceId == null) {
      final workbench = context.read<WorkbenchCubit>();
      for (final entry in workbench.state.byWorkspace.entries) {
        final active = entry.value.activeTabId;
        if (active?.kind == WorkbenchTabKind.file) {
          path = active!.id;
          workspaceId = entry.key;
          break;
        }
      }
    }
    final readOnly =
        path != null &&
        workspaceId != null &&
        editorCubit.isReadOnly(workspaceId, path);

    final specs = <TpActionMenuSpec>[
      if (!readOnly)
        TpActionMenuSpec.item(
          icon: Icons.content_cut,
          label: l10n.editorCut,
          onAction: controller.cut,
        ),
      TpActionMenuSpec.item(
        icon: Icons.content_copy,
        label: l10n.editorCopy,
        onAction: controller.copy,
      ),
      if (!readOnly)
        TpActionMenuSpec.item(
          icon: Icons.content_paste,
          label: l10n.editorPaste,
          onAction: controller.paste,
        ),
      const TpActionMenuSpec.divider(),
      if (path != null && workspaceId != null)
        TpActionMenuSpec.item(
          icon: Icons.terminal_outlined,
          label: l10n.editorSendToAgent,
          onAction: () {
            final openPath = path;
            final openWorkspace = workspaceId;
            if (openPath == null || openWorkspace == null) return;
            unawaited(
              _sendSelectionToAgent(
                context,
                controller: controller,
                path: openPath,
                workspaceId: openWorkspace,
              ),
            );
          },
        ),
      if (path != null && workspaceId != null)
        TpActionMenuSpec.item(
          icon: Icons.format_list_numbered,
          label: l10n.editorCopyPathWithLines,
          onAction: () {
            final openPath = path;
            final openWorkspace = workspaceId;
            if (openPath == null || openWorkspace == null) return;
            unawaited(
              _copyPathWithLines(
                context,
                controller: controller,
                path: openPath,
                workspaceId: openWorkspace,
              ),
            );
          },
        ),
      const TpActionMenuSpec.divider(),
      TpActionMenuSpec.item(
        icon: Icons.select_all,
        label: l10n.editorSelectAll,
        onAction: controller.selectAll,
      ),
      if (!readOnly && controller.canUndo)
        TpActionMenuSpec.item(
          icon: Icons.undo,
          label: l10n.editorUndoEdit,
          onAction: controller.undo,
        ),
      if (!readOnly && controller.canRedo)
        TpActionMenuSpec.item(
          icon: Icons.redo,
          label: l10n.editorRedoEdit,
          onAction: controller.redo,
        ),
    ];

    unawaited(_showMenu(context, anchors.primaryAnchor, specs));
  }

  /// Stages the editor's selection (or the caret's line when collapsed) into
  /// the workspace's active session terminal as a `@path#L1-2` agent mention
  /// and switches the workbench pane to that terminal.
  Future<void> _sendSelectionToAgent(
    BuildContext context, {
    required CodeLineEditingController controller,
    required String path,
    required String workspaceId,
  }) async {
    final selection = controller.selection;
    // re-editor line indices are 0-based; mentions are 1-based like the
    // gutter and every agent CLI's file:line syntax.
    final startLine = selection.startIndex + 1;
    final endLine = selection.endIndex + 1;

    final chat = context.read<ChatCubit>();
    final workspace = chat.state.workspaces
        .where((w) => w.workspaceId == workspaceId)
        .firstOrNull;
    final roots = workspace?.folderPaths ?? const <String>[];

    // Active session terminal for this workspace: foreground follows
    // ChatState; kept-alive background tabs follow their saved bucket —
    // same rules as scopedActiveSessionId.
    final activeSessionId = scopedActiveSessionId(chat, workspaceId);
    final tab = activeSessionId == null
        ? null
        : chat.tabStore.openTabBySessionId(activeSessionId);
    final session = tab == null
        ? null
        : (tab.memberShells[tab.selectedMemberId] ?? tab.resumeSession);
    if (session == null || !session.transportReadyForIo) {
      _showAgentReferenceToast(context, AgentReferenceOutcome.noSession);
      return;
    }

    final outcome = await const EditorAgentReferenceSender().send(
      workspaceRoots: roots,
      absolutePath: path,
      startLine: startLine,
      endLine: endLine,

      sink: session.input,
      terminalNamespace: session.runtimeTarget.namespace,
    );
    if (!context.mounted) return;
    _showAgentReferenceToast(context, outcome);
    if (outcome != AgentReferenceOutcome.delivered) return;

    // Flip the workbench center pane to the session terminal so the staged
    // mention is visible where the user will type their question.
    context.read<WorkbenchCubit>().ensureTab(
          workspaceId,
          WorkbenchTabId.session(tab!.info.id),
        );
  }

  /// Copies the selection's (or caret's) line range as `path#L5-10` — the
  /// agent-mention grammar minus the `@` sigil, for pasting anywhere.
  Future<void> _copyPathWithLines(
    BuildContext context, {
    required CodeLineEditingController controller,
    required String path,
    required String workspaceId,
  }) async {
    final selection = controller.selection;
    final startLine = selection.startIndex + 1;
    final endLine = selection.endIndex + 1;

    final chat = context.read<ChatCubit>();
    final workspace = chat.state.workspaces
        .where((w) => w.workspaceId == workspaceId)
        .firstOrNull;
    final roots = workspace?.folderPaths ?? const <String>[];

    final reference = const EditorAgentClipboardReferenceResolver().resolve(
      workspaceRoots: roots,
      absolutePath: path,
      startLine: startLine,
      endLine: endLine,
    );
    if (reference == null) {
      if (context.mounted) {
        _showAgentReferenceToast(
          context,
          AgentReferenceOutcome.noWorkspaceRoot,
        );
      }
      return;
    }
    await Clipboard.setData(ClipboardData(text: reference));
    if (!context.mounted) return;
    AppToast.show(
      context,
      message: context.l10n.pathCopied(reference),
      variant: TpToastVariant.success,
      record: false,
    );
  }

  void _showAgentReferenceToast(
    BuildContext context,
    AgentReferenceOutcome outcome,
  ) {
    final l10n = context.l10n;
    final message = switch (outcome) {
      AgentReferenceOutcome.delivered => l10n.agentReferenceSent,
      AgentReferenceOutcome.noSession => l10n.agentReferenceNoSession,
      AgentReferenceOutcome.noWorkspaceRoot => l10n.agentReferenceNoRoot,
      AgentReferenceOutcome.crossNamespace => l10n.agentReferenceCrossMachine,
    };
    AppToast.show(context, message: message);
  }


  Future<void> _showMenu(
    BuildContext context,
    Offset globalPosition,
    List<TpActionMenuSpec> specs,
  ) async {
    onMenuOpenChanged(true);
    try {
      await showTpActionMenuFromSpecs<void>(
        context: context,
        globalPosition: globalPosition,
        specs: specs,
      );
    } finally {
      onMenuOpenChanged(false);
    }
  }
}
