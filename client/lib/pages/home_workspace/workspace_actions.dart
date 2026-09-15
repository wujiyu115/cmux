import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../cubits/chat_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../repositories/session_repository.dart';
import '../../utils/debounce/debounce.dart';
import '../../utils/workspace/workspace_display_name.dart';
import 'workspace/config/workspace_folders_section.dart';
import 'workspace/root_sandbox_env_opt_in_tile.dart';

/// Whether [location] is the workbench route for [workspaceId].
bool isViewingWorkspaceRoute(String location, String workspaceId) {
  final segments = Uri.parse(location).pathSegments;
  return segments.length >= 3 &&
      segments[0] == 'home-v2' &&
      segments[1] == 'workspace' &&
      segments[2] == workspaceId;
}

/// Navigates away from a deleted workspace when the workbench route is active.
/// Call after the delete confirmation dialog has been closed.
void completeWorkspaceDeleteNavigation(
  GoRouter router, {
  required String deletedWorkspaceId,
  required String currentLocation,
}) {
  if (isViewingWorkspaceRoute(currentLocation, deletedWorkspaceId)) {
    router.go('/home-v2');
    return;
  }
  router.go(currentLocation);
}

Future<void> showRenameWorkspaceDialog(
  BuildContext context,
  Workspace workspace, {
  String? title,
}) async {
  final l10n = context.l10n;
  final display = await showTpTextPromptDialog(
    context,
    title: title ?? l10n.homeWorkspaceRenameWorkspace,
    initialText: workspace.display,
    hintText: workspace.localizedName(l10n),
    confirmLabel: l10n.save,
  );
  if (display == null || !context.mounted) return;
  final repo = context.read<SessionRepository>();
  await context.read<ChatCubit>().updateWorkspaceMetadata(
    repo,
    workspace.workspaceId,
    display: display,
  );
}

Future<void> cloneWorkspace(BuildContext context, Workspace workspace) async {
  final l10n = context.l10n;
  final repo = context.read<SessionRepository>();
  final baseName = workspace.localizedName(l10n);
  final display = l10n.homeWorkspaceCloneWorkspaceDisplayName(baseName);

  try {
    final cloned = await context.read<ChatCubit>().cloneWorkspace(
      repo,
      workspace.workspaceId,
      display: display,
    );
    if (!context.mounted) return;
    AppToast.show(
      context,
      message: l10n.homeWorkspaceCloneWorkspaceSuccess(baseName),
      variant: TpToastVariant.success,
    );
    context.go('/home-v2/workspace/${cloned.workspaceId}');
  } on Object catch (error) {
    if (!context.mounted) return;
    AppToast.show(
      context,
      message: '${l10n.homeWorkspaceCloneWorkspaceFailed}: $error',
      variant: TpToastVariant.error,
    );
  }
}

Future<void> confirmDeleteWorkspace(
  BuildContext context,
  Workspace workspace,
) async {
  final l10n = context.l10n;
  final repo = context.read<SessionRepository>();
  final chatCubit = context.read<ChatCubit>();
  final name = workspace.localizedName(l10n);
  final router = GoRouter.of(context);
  final currentLocation = GoRouterState.of(context).uri.toString();
  await showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => TpDialog(
      maxWidth: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.deleteWorkspace),
          const SizedBox(height: 16),
          Text(l10n.deleteWorkspaceConfirm(name)),
          TpDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
                onPressed: throttledAsync(
                  'home_workspace_card_delete_workspace',
                  () async {
                    await chatCubit.deleteWorkspace(
                      repo,
                      workspace.workspaceId,
                    );
                    if (ctx.mounted) {
                      Navigator.of(ctx).pop();
                    }
                    completeWorkspaceDeleteNavigation(
                      router,
                      deletedWorkspaceId: workspace.workspaceId,
                      currentLocation: currentLocation,
                    );
                  },
                ),
                child: Text(l10n.delete),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Edits the workspace's directories + machines in a dialog. Edits apply on
/// change (same editor the manage view hosts), so the dialog carries no save
/// action — close dismisses once the last change has settled.
Future<void> showWorkspaceFoldersDialog(
  BuildContext context,
  Workspace workspace,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => TpDialog(
      maxWidth: 680,
      maxHeight: 560,
      child: TpDialogPinnedLayout(
        header: TpDialogHeader(
          title: context.l10n.workspaceFoldersSectionTitle,
          onClose: () => Navigator.of(ctx).pop(),
        ),
        body: WorkspaceFoldersSection(
          workspace: workspace,
          lockTargets: true,
          embedded: true,
        ),
      ),
    ),
  );
}

/// Workspace-scoped root sandbox env opt-in in a dialog. The toggle applies
/// immediately (with the trust-boundary confirm), mirroring the manage tile.
Future<void> showWorkspaceRootSandboxDialog(
  BuildContext context,
  Workspace workspace,
) async {
  final l10n = context.l10n;
  final live = context.read<ChatCubit>().state.workspaces.firstWhere(
        (w) => w.workspaceId == workspace.workspaceId,
        orElse: () => workspace,
      );
  await showDialog<void>(
    context: context,
    builder: (ctx) => TpDialog(
      maxWidth: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(
            title: l10n.rootSandboxEnvOptInTitle,
            onClose: () => Navigator.of(ctx).pop(),
          ),
          RootSandboxEnvOptInTile(
            workspaceLabel: live.localizedName(l10n),
            optedIn: live.rootSandboxEnvOptIn,
            showDividerBelow: false,
            onChanged: (next) {
              context.read<ChatCubit>().updateWorkspaceMetadata(
                    context.read<SessionRepository>(),
                    live.workspaceId,
                    rootSandboxEnvOptIn: next,
                  );
            },
          ),
        ],
      ),
    ),
  );
}
