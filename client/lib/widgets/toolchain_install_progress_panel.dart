import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../l10n/l10n_extensions.dart';
import '../services/cli/git_installer.dart';

/// Progress panel for a toolchain (git) install run.
class ToolchainInstallProgressPanel extends StatelessWidget {
  const ToolchainInstallProgressPanel({
    super.key,
    required this.phase,
    this.logLines = const [],
  });

  final GitInstallPhase phase;
  final List<String> logLines;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);

    return TpCard.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(
              borderRadius: BorderRadius.circular(4),
              backgroundColor: cs.surfaceContainerHighest,
            ),
            const SizedBox(height: 10),
            Text(_phaseLabel(l10n, phase), style: styles.mdMedium),
            if (logLines.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SingleChildScrollView(
                  reverse: true,
                  child: SelectableText(
                    logLines.join('\n'),
                    style: styles.mutedSm,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _phaseLabel(AppLocalizations l10n, GitInstallPhase phase) {
    return switch (phase) {
      GitInstallPhase.checking => l10n.cliInstallProgressCheckingNpm,
      GitInstallPhase.installing => l10n.cliInstallProgressInstallingCli,
      GitInstallPhase.locating => l10n.cliInstallProgressLocatingExecutable,
    };
  }
}
