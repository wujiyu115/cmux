import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/workspace_accent.dart';
import '../../theme/workspace_accent_palette.dart';

/// Result of the accent picker. `null` [accent] means "no accent / theme
/// default"; the outer `Future` resolving to `null` means the user cancelled.
@immutable
class WorkspaceAccentPick {
  const WorkspaceAccentPick(this.accent);

  final WorkspaceAccentPreset? accent;
}

/// A swatch grid (图 12b): pick a preset accent or clear it. Returns `null`
/// when dismissed without choosing.
Future<WorkspaceAccentPick?> showWorkspaceAccentPickerDialog(
  BuildContext context, {
  WorkspaceAccentPreset? current,
}) {
  final l10n = context.l10n;
  return showDialog<WorkspaceAccentPick>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return TpDialog(
        maxWidth: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(
              title: l10n.workspaceAccentColor,
              onClose: () => Navigator.of(ctx).pop(),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _AccentDot(
                  color: cs.outlineVariant,
                  selected: current == null,
                  child: Icon(
                    Icons.format_color_reset_outlined,
                    size: ctx.tpIconSizes.sm,
                    color: cs.onSurfaceVariant,
                  ),
                  onTap: () =>
                      Navigator.of(ctx).pop(const WorkspaceAccentPick(null)),
                ),
                for (var i = 0; i < workspaceAccentPresetCount; i++)
                  _AccentDot(
                    color: workspaceAccentColorForIndex(ctx, i),
                    selected: current?.index == i,
                    onTap: () => Navigator.of(
                      ctx,
                    ).pop(WorkspaceAccentPick(WorkspaceAccentPreset(i))),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.color,
    required this.selected,
    required this.onTap,
    this.child,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? cs.onSurface : Colors.transparent,
            width: 2,
          ),
        ),
        child: selected && child == null
            ? Icon(Icons.check, size: context.tpIconSizes.sm, color: Colors.white)
            : child,
      ),
    );
  }
}
