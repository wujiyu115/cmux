import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/vcs/svn_service.dart';

/// Rows of one svn working copy's changes. Checkboxes select the commit
/// set (svn has no staging); badge + path + trailing revision per row.
class SvnChangesList extends StatelessWidget {
  const SvnChangesList({
    required this.rows,
    required this.selectedPaths,
    required this.onToggle,
    required this.onOpenDiff,
    required this.onRevert,
    required this.onAdd,
    super.key,
  });

  final List<SvnFileChange> rows;
  final Set<String> selectedPaths;
  final void Function(String path) onToggle;
  final void Function(SvnFileChange row) onOpenDiff;
  final void Function(List<SvnFileChange> rows) onRevert;
  final void Function(SvnFileChange row) onAdd;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          context.l10n.svnNoChanges,
          style: TpTextStyles.of(context).xsColored(
            Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final row in rows) _SvnRow(row: row, list: this),
      ],
    );
  }
}

class _SvnRow extends StatelessWidget {
  const _SvnRow({required this.row, required this.list});

  final SvnFileChange row;
  final SvnChangesList list;

  bool get _selected => list.selectedPaths.contains(row.path);

  bool get _revertible =>
      row.kind == SvnChangeKind.modified ||
      row.kind == SvnChangeKind.added ||
      row.kind == SvnChangeKind.replaced;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => list.onOpenDiff(row),
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 24,
              child: Checkbox(
                value: _selected,
                visualDensity: VisualDensity.compact,
                onChanged: (_) => list.onToggle(row.path),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              row.badge,
              style: TpTextStyles.of(context).xsSemiboldColored(
                _badgeColor(cs, row.kind),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                row.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TpTextStyles.of(
                  context,
                ).xsColored(cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _badgeColor(ColorScheme cs, SvnChangeKind kind) {
    return switch (kind) {
      SvnChangeKind.conflicted => cs.error,
      SvnChangeKind.missing => cs.error,
      SvnChangeKind.unversioned => cs.tertiary,
      _ => cs.primary,
    };
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final l10n = context.l10n;
    showTpActionMenuFromSpecs<void>(
      context: context,
      globalPosition: position,
      specs: [
        TpActionMenuSpec.item(
          icon: Icons.open_in_new,
          label: l10n.svnOpenDiff,
          onAction: () => list.onOpenDiff(row),
        ),
        if (_revertible)
          TpActionMenuSpec.item(
            icon: Icons.undo,
            label: l10n.svnRevertAction,
            onAction: () => list.onRevert([row]),
          ),
        if (row.kind == SvnChangeKind.unversioned)
          TpActionMenuSpec.item(
            icon: Icons.add,
            label: l10n.svnAdd,
            onAction: () => list.onAdd(row),
          ),
      ],
    );
  }
}
