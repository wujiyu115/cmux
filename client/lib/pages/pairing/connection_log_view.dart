import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../theme/app_fonts.dart';
import '../../theme/app_typography_scale.dart';
import '../../utils/ui/app_keys.dart';

/// Live connection diagnostics. LAN pairing fails in opaque ways — wrong IP,
/// firewall, expired code — so the confirm flow shows every step the client
/// logs, newest first.
///
/// Collapsible, but the lines stay mounted either way: this is diagnostic detail
/// that shouldn't dominate the screen, yet re-creating the list on every toggle
/// would drop the scroll position mid-connect.
class ConnectionLogView extends StatefulWidget {
  const ConnectionLogView({super.key});

  @override
  State<ConnectionLogView> createState() => _ConnectionLogViewState();
}

class _ConnectionLogViewState extends State<ConnectionLogView> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PairingClientCubit, PairingClientState>(
      buildWhen: (a, b) => a.logs != b.logs,
      builder: (context, state) {
        final cs = Theme.of(context).colorScheme;
        return DecoratedBox(
          key: AppKeys.pairingConnectionLog,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(context.tpSpacing.md),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Summary(
                count: state.logs.length,
                expanded: _expanded,
                onTap: () => setState(() => _expanded = !_expanded),
              ),
              Offstage(
                offstage: !_expanded,
                child: _Lines(logs: state.logs),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final typography = context.appTypography;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.md,
            vertical: spacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.pairingConnectionLogTitle,
                  style: TpTextStyles.of(context).xsColored(cs.onSurfaceVariant),
                ),
              ),
              Text(
                l10n.pairingLogLineCount(count),
                style: appMonoTextStyle(
                  context,
                  fontSize: typography.bodySmall,
                  color: cs.onSurfaceVariant,
                ),
              ),
              SizedBox(width: spacing.sm),
              AnimatedRotation(
                turns: expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 160),
                child: Icon(
                  Icons.chevron_right,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines({required this.logs});

  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spacing = context.tpSpacing;
    final typography = context.appTypography;
    final mono = appMonoTextStyle(
      context,
      fontSize: typography.labelSmall,
      height: 1.5,
      color: cs.onSurfaceVariant,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.md, 0, spacing.md, spacing.md),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 132),
        child: logs.isEmpty
            ? Text(context.l10n.pairingWaitingForConnection, style: mono)
            : ListView.builder(
                reverse: true,
                shrinkWrap: true,
                itemCount: logs.length,
                itemBuilder: (context, i) =>
                    Text(logs[logs.length - 1 - i], style: mono),
              ),
      ),
    );
  }
}
