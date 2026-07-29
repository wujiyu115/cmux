import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/plugin.dart';
import '../../utils/github/github_source_url.dart';
import '../../widgets/github_details_button.dart';
import 'package:teampilot/theme/workspace_surface_layers.dart';

class TeamPluginRow extends StatelessWidget {
  const TeamPluginRow({
    super.key,
    required this.plugin,
    required this.assigned,
    required this.onAssignedChanged,
    this.conflictDir,
  });

  final Plugin plugin;
  final bool assigned;
  final ValueChanged<bool> onAssignedChanged;
  final String? conflictDir;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final textBase = cs.onSurface;
    final sourceLabel =
        plugin.marketplaceOwner != null && plugin.marketplaceName != null
        ? '${plugin.marketplaceOwner}/${plugin.marketplaceName}'
        : 'local';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: workspaceInsetDecoration(cs, radius: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          plugin.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TpTextStyles.of(context).mdBoldColored(textBase,),
                        ),
                      ),
                      if (plugin.version.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          'v${plugin.version}',
                          style: TpTextStyles.of(context).xsSemiboldColored(textBase.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Text(
                        sourceLabel,
                        style: TpTextStyles.of(context).xsColored(textBase.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  if (plugin.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      plugin.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TpTextStyles.of(context).smColored(textBase.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                  if (conflictDir != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: context.tpIconSizes.md,
                          color: cs.tertiary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            l10n.teamPluginsNameConflict(conflictDir!),
                            style: TpTextStyles.of(context).xsColored(textBase.withValues(alpha: 0.65),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            GithubDetailsButton(
              url: plugin.githubBrowseUrl,
              label: l10n.pluginsCardDetails,
            ),
            const SizedBox(width: 8),
            Switch(value: assigned, onChanged: onAssignedChanged),
          ],
        ),
      ),
    );
  }
}

class TeamMissingPluginRow extends StatelessWidget {
  const TeamMissingPluginRow({
    super.key,
    required this.pluginId,
    required this.onRemove,
  });

  final String pluginId;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final textBase = cs.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: workspaceInsetDecoration(
          cs,
          radius: 10,
        ).copyWith(color: cs.surfaceContainerHighest.withValues(alpha: 0.35)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pluginId,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TpTextStyles.of(context).mdSemiboldColored(textBase.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.teamPluginsMissingLabel,
                    style: TpTextStyles.of(
                      context,
                    ).xsColored(cs.error.withValues(alpha: 0.85)),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onRemove,
              child: Text(l10n.teamPluginsRemoveMissing),
            ),
          ],
        ),
      ),
    );
  }
}
