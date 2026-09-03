import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import 'pairing_sheet_parts.dart';

/// One action from [showMirrorActionsSheet].
enum MirrorAction { gitDiff, scrollToLatest }

/// The mirror nav bar's second-level sheet: what the trailing more icon opens.
///
/// A sheet rather than inline nav actions because a 52px row is the easiest
/// target a phone offers, and because the git-diff entry needs the changed-file
/// count next to it to be worth tapping.
Future<MirrorAction?> showMirrorActionsSheet(
  BuildContext context, {
  int? changeCount,
}) {
  return showPairingSheet<MirrorAction>(
    context: context,
    builder: (sheetContext) {
      final l10n = sheetContext.l10n;
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PairingSheetGrab(),
            PairingSheetHead(
              title: l10n.mirrorActionsTitle,
              onClose: () => Navigator.of(sheetContext).pop(),
            ),
            _ActionRow(
              icon: Icons.difference_outlined,
              label: l10n.gitDiff,
              // Same semantics as the nav-bar badge: null is "unknown", which
              // must not claim a clean repo by showing 0.
              trailing: (changeCount == null || changeCount == 0)
                  ? null
                  : l10n.mirrorActionChangedCount(changeCount),
              onTap: () => Navigator.of(sheetContext).pop(MirrorAction.gitDiff),
            ),
            _ActionRow(
              icon: Icons.vertical_align_bottom,
              label: l10n.mirrorScrollToLatest,
              onTap: () =>
                  Navigator.of(sheetContext).pop(MirrorAction.scrollToLatest),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// Prototype `.sheet-opt` shape — 52 tall, 20 inset — as an action row: leading
/// glyph, label, optional muted trailing counter.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: cs.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, color: cs.onSurface),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              Text(
                trailing!,
                style: TextStyle(
                  fontSize: 13.5,
                  color: pairingMutedColor(cs),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
