import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';

/// Floating copy action shown over the mirrored terminal while a touch
/// selection is live.
///
/// Long-press selection works on the phone, but a phone has no Ctrl+Shift+C
/// and no right-click menu, so without this chip a selection is something the
/// user can see and do nothing with. The mirror page mounts it only while
/// `TerminalController.selectionActive`; tapping it copies the selection text
/// to the system clipboard and clears the selection.
class MirrorSelectionBar extends StatelessWidget {
  const MirrorSelectionBar({super.key, required this.onCopy});

  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Material(
      // Elevated chip over the dark terminal grid: theme surface reads in both
      // light and dark terminal themes because it contrasts with the grid, not
      // with the app background.
      color: cs.surfaceContainerHighest,
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: AppKeys.pairingMirrorCopyButton,
        onTap: onCopy,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.copy_rounded, size: 16, color: cs.onSurface),
              const SizedBox(width: 6),
              Text(
                l10n.pairingMirrorCopySelection,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
