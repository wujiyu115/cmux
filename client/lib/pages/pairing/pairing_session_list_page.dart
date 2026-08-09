import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../theme/app_fonts.dart';
import '../../theme/app_typography_scale.dart';
import '../../utils/ui/app_keys.dart';
import 'pairing_nav_bar.dart';
import 'pairing_workspace_group.dart';

/// A paired desktop's workspace tree: every workspace — including dormant ones
/// with nothing running — as a collapsible group listing its live terminals.
/// Tapping one opens its live mirror; a dormant workspace offers to open a
/// terminal host-side first.
class PairingSessionListPage extends StatelessWidget {
  const PairingSessionListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PairingClientCubit, PairingClientState>(
      builder: (context, state) {
        final l10n = context.l10n;
        final cubit = context.read<PairingClientCubit>();
        final spacing = context.tpSpacing;
        return Scaffold(
          key: AppKeys.pairingSessionListPage,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PairingNavBar(
                  title: state.activeHostName ?? l10n.pairingDesktopFallback,
                  onBack: cubit.cancel,
                  trailing: PairingNavAction(
                    icon: Icons.refresh,
                    tooltip: l10n.pairingRefresh,
                    onTap: cubit.refreshWorkspaces,
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: cubit.refreshWorkspaces,
                    child: ListView(
                      // A ListView even when empty, so pull-to-refresh keeps
                      // working with nothing to show.
                      padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                      children: [
                        const _ConnectionRow(),
                        if (state.workspaces.isEmpty)
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.5,
                            child: Center(child: Text(l10n.pairingNoWorkspaces)),
                          )
                        else
                          for (final workspace in state.workspaces)
                            PairingWorkspaceGroup(
                              workspace: workspace,
                              activatingKey: state.activatingKey,
                              onOpenNode: cubit.activateAndOpen,
                            ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final typography = context.appTypography;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacing.md),
      child: Row(
        children: [
          TpStatusBadge(
            label: context.l10n.pairingConnectedBadge,
            tone: TpStatusBadgeTone.success,
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: BlocSelector<PairingClientCubit, PairingClientState, String?>(
              selector: (state) => state.activeHostUrl,
              builder: (context, url) => url == null
                  ? const SizedBox.shrink()
                  : Text(
                      url,
                      style: appMonoTextStyle(
                        context,
                        fontSize: typography.bodySmall,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
