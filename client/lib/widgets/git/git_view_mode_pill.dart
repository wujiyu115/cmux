import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/layout_preferences.dart';

/// Tree | flat segmented pill for the Source Control changes list, matching
/// editor chrome (border + selected fill) — same shape as the diff toolbar's
/// view-mode pill.
class GitViewModePill extends StatelessWidget {
  const GitViewModePill({
    required this.mode,
    required this.onModeChanged,
    super.key,
  });

  final GitChangesViewMode mode;
  final ValueChanged<GitChangesViewMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = cs.onSurface;
    return Container(
      height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _GitViewModeSegment(
            icon: Icons.account_tree_outlined,
            tooltip: context.l10n.gitViewModeTreeTooltip,
            selected: mode == GitChangesViewMode.tree,
            color: color,
            onTap: () => onModeChanged(GitChangesViewMode.tree),
          ),
          Container(width: 1, height: 14, color: cs.outlineVariant),
          _GitViewModeSegment(
            icon: Icons.view_headline_outlined,
            tooltip: context.l10n.gitViewModeFlatTooltip,
            selected: mode == GitChangesViewMode.flat,
            color: color,
            onTap: () => onModeChanged(GitChangesViewMode.flat),
          ),
        ],
      ),
    );
  }
}

class _GitViewModeSegment extends StatelessWidget {
  const _GitViewModeSegment({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected
            ? cs.onSurface.withValues(alpha: 0.12)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: color.withValues(alpha: 0.12),
          splashColor: color.withValues(alpha: 0.2),
          child: SizedBox(
            width: 30,
            height: 28,
            child: Icon(icon, size: context.tpIconSizes.sm, color: color),
          ),
        ),
      ),
    );
  }
}
