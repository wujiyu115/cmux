import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/pairing/pairing_client.dart';
import '../../utils/ui/app_keys.dart';

/// A paired desktop's full workspace tree (orca-style): every workspace —
/// including dormant ones with no live terminal — as an [ExpansionTile], each
/// listing its persisted chat sessions and its live workspace panes. Tapping any
/// node activates it host-side (if needed) then opens its live mirror.
class PairingSessionListPage extends StatelessWidget {
  const PairingSessionListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PairingClientCubit, PairingClientState>(
      builder: (context, state) {
        final l10n = context.l10n;
        final cubit = context.read<PairingClientCubit>();
        return Scaffold(
          key: AppKeys.pairingSessionListPage,
          appBar: AppBar(
            title: Text(state.activeHostName ?? l10n.pairingDesktopFallback),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: cubit.cancel,
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: l10n.pairingRefresh,
                onPressed: cubit.refreshWorkspaces,
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: cubit.refreshWorkspaces,
            child: state.workspaces.isEmpty
                ? ListView(
                    // ListView (not Center) so pull-to-refresh works when empty.
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.6,
                        child: Center(child: Text(l10n.pairingNoWorkspaces)),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: state.workspaces.length,
                    itemBuilder: (context, i) => _WorkspaceTile(
                      workspace: state.workspaces[i],
                      activatingKey: state.activatingKey,
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({required this.workspace, this.activatingKey});

  final PairingWorkspaceNode workspace;
  final String? activatingKey;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final count = workspace.sessions.length + workspace.panes.length;
    return ExpansionTile(
      key: AppKeys.pairingWorkspaceHeader(workspace.workspaceId),
      initiallyExpanded: workspace.panes.isNotEmpty,
      leading: const Icon(Icons.folder_outlined),
      title: Text(
        workspace.title.isEmpty ? workspace.workspaceId : workspace.title,
      ),
      subtitle: Text('$count'),
      childrenPadding: const EdgeInsets.only(bottom: 4),
      children: [
        if (workspace.sessions.isNotEmpty) ...[
          _GroupHeader(l10n.pairingPersistedSessions),
          for (final s in workspace.sessions)
            _SessionNodeTile(
              node: s,
              busy: activatingKey == s.nodeKey,
            ),
        ],
        if (workspace.panes.isNotEmpty) ...[
          _GroupHeader(l10n.pairingLiveTerminals),
          for (final p in workspace.panes)
            _SessionNodeTile(
              node: p,
              busy: activatingKey == p.nodeKey,
            ),
        ],
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1.1,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

class _SessionNodeTile extends StatelessWidget {
  const _SessionNodeTile({required this.node, this.busy = false});

  final PairingSessionNode node;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListTile(
      key: AppKeys.pairingSessionNode(node.nodeKey),
      contentPadding: const EdgeInsets.only(left: 32, right: 16),
      leading: Icon(
        node.kind == 'chat'
            ? Icons.chat_bubble_outline
            : Icons.terminal_outlined,
      ),
      title: Text(node.title.isEmpty ? node.nodeKey : node.title),
      subtitle: node.subtitle.isEmpty ? null : Text(node.subtitle),
      trailing: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : _LivenessBadge(
              live: node.live,
              geometry: node.live ? '${node.cols}×${node.rows}' : null,
              liveLabel: l10n.pairingLiveBadge,
              offlineLabel: l10n.pairingOfflineBadge,
            ),
      enabled: !busy,
      onTap: () => context.read<PairingClientCubit>().activateAndOpen(node),
    );
  }
}

class _LivenessBadge extends StatelessWidget {
  const _LivenessBadge({
    required this.live,
    required this.liveLabel,
    required this.offlineLabel,
    this.geometry,
  });

  final bool live;
  final String liveLabel;
  final String offlineLabel;
  final String? geometry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = live ? scheme.primary : scheme.outline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (geometry != null) ...[
          Text(
            geometry!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.outline,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            live ? liveLabel : offlineLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
