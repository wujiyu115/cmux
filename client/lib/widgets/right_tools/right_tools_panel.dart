import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/layout_preferences.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import '../../utils/ui/app_keys.dart';
import 'right_tools_lifecycle.dart';
import 'right_tools_tool_preferences.dart';
import 'right_tools_tool_views.dart';

class RightToolsPanel extends StatefulWidget {
  const RightToolsPanel({
    required this.cwd,
    required this.workspaceId,
    this.toolsScopeId,
    this.additionalPaths = const [],
    this.preferences = const LayoutPreferences(),
    this.panelKey = AppKeys.rightToolsPanel,
    this.dismissDrawerOnAction = false,
    super.key,
  });

  final LayoutPreferences preferences;
  final Key panelKey;
  final bool dismissDrawerOnAction;
  final String cwd;
  final List<String> additionalPaths;
  final String workspaceId;
  final String? toolsScopeId;

  String get _toolsScopeId => toolsScopeId ?? workspaceId;

  @override
  State<RightToolsPanel> createState() => _RightToolsPanelState();
}

class _RightToolsPanelState extends State<RightToolsPanel> {
  RightToolsToolPreferences get _toolPreferences =>
      RightToolsToolPreferences.from(widget.preferences);

  @override
  Widget build(BuildContext context) {
    if (!widget.preferences.rightToolsVisible ||
        !_toolPreferences.needsLifecycleHost) {
      return const SizedBox.shrink();
    }
    return RightToolsLifecycleHost(
      cwd: widget.cwd,
      additionalPaths: widget.additionalPaths,
      workspaceId: widget.workspaceId,
      preferences: _toolPreferences,
      child: _RightToolsPanelBody(
        panelKey: widget.panelKey,
        toolPreferences: _toolPreferences,
        cwd: widget.cwd,
        workspaceId: widget.workspaceId,
        toolsScopeId: widget._toolsScopeId,
        dismissDrawerOnAction: widget.dismissDrawerOnAction,
      ),
    );
  }
}

class _RightToolsPanelBody extends StatelessWidget {
  const _RightToolsPanelBody({
    required this.panelKey,
    required this.toolPreferences,
    required this.cwd,
    required this.workspaceId,
    required this.toolsScopeId,
    required this.dismissDrawerOnAction,
  });

  final Key panelKey;
  final RightToolsToolPreferences toolPreferences;
  final String cwd;
  final String workspaceId;
  final String toolsScopeId;
  final bool dismissDrawerOnAction;

  @override
  Widget build(BuildContext context) {
    final lifecycle = RightToolsLifecycle.of(context);
    final scope = lifecycle.scope;
    final tools = scope.tools;
    final fileTreeCubit = lifecycle.fileTreeCubit;

    if (scope.isReady && tools != null && fileTreeCubit != null) {
      return RightToolsWorkingTurnListener(
        onTurnEnd: lifecycle.pokeOnTurnEnd,
        child: Container(
          key: panelKey,
          child: RightToolsToolViews(
            preferences: toolPreferences,
            cwd: cwd,
            workspaceId: workspaceId,
            toolsScopeId: toolsScopeId,
            dismissDrawerOnAction: dismissDrawerOnAction,
            fileTreeCubit: fileTreeCubit,
            workContext: tools.context,
            scope: scope,
          ),
        ),
      );
    }

    if (!scope.resolving && scope.resolveError != null && tools == null) {
      return _RightToolsResolveError(panelKey: panelKey);
    }

    return const SizedBox.shrink();
  }
}

class _RightToolsResolveError extends StatelessWidget {
  const _RightToolsResolveError({required this.panelKey});

  final Key panelKey;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final styles = TpTextStyles.of(context);
    return Container(
      key: panelKey,
      padding: const EdgeInsets.all(16),
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 28,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.workspaceToolsResolveFailed,
            textAlign: TextAlign.center,
            style: styles.smSemibold,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.workspaceToolsResolveFailedHint,
            textAlign: TextAlign.center,
            style: styles.smColored(theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => context.read<WorkspaceToolsScopeCubit>().retry(),
            child: Text(l10n.sessionRetryButton),
          ),
        ],
      ),
    );
  }
}
