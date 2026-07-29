import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/skill.dart';
import '../../utils/github/github_source_url.dart';
import '../../widgets/github_details_button.dart';
import 'package:teampilot/theme/workspace_surface_layers.dart';

class TeamSkillRow extends StatelessWidget {
  const TeamSkillRow({
    super.key,
    required this.skill,
    required this.assigned,
    required this.onAssignedChanged,
  });

  final Skill skill;
  final bool assigned;
  final ValueChanged<bool> onAssignedChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final textBase = cs.onSurface;
    final sourceLabel = skill.repoOwner != null && skill.repoName != null
        ? '${skill.repoOwner}/${skill.repoName}'
        : l10n.skillsLocal;

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
                          skill.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TpTextStyles.of(
                            context,
                          ).mdBoldColored(textBase),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        sourceLabel,
                        style: TpTextStyles.of(
                          context,
                        ).xsColored(textBase.withValues(alpha: 0.5)),
                      ),
                    ],
                  ),
                  if (skill.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      skill.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TpTextStyles.of(
                        context,
                      ).smColored(textBase.withValues(alpha: 0.6)),
                    ),
                  ],
                ],
              ),
            ),
            GithubDetailsButton(
              url: skill.githubBrowseUrl,
              label: l10n.skillsCardDetails,
            ),
            const SizedBox(width: 8),
            Switch(value: assigned, onChanged: onAssignedChanged),
          ],
        ),
      ),
    );
  }
}
