import 'package:flutter/material.dart';

import '../../cubits/pairing_client_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../utils/ui/app_keys.dart';
import 'mobile_chrome.dart';
import 'pairing_mirror_page.dart';
import 'pairing_session_list_page.dart';
import 'pairing_tablet_layout.dart';

/// Tablet (iPad / Android large screen) root for the connected half of the
/// pairing flow: the workspace
/// tree as a fixed sidebar, and the mirror in the remaining space.
///
/// Exists because the phone shell's navigation is a whole-screen swap — see
/// [PairingTabletLayout] for why that is wrong on a tablet. Here the sidebar is
/// never torn down, so a workspace the reader expanded stays expanded, and
/// [PairingClientPhase.mirroring] only changes the right pane. Closing the
/// mirror ([PairingClientCubit.leaveMirror]) leaves the list exactly as it was.
///
/// A sidebar-less state is not possible: the shell only renders for `connected`
/// / `mirroring`, and `connected` without a selection is the placeholder.
class PairingTabletShell extends StatelessWidget {
  const PairingTabletShell({super.key, required this.state});

  /// The phase the shell was built for. Comes from [PairingMobileShell]'s
  /// `BlocBuilder`, which already filters on phase / catalog id / generation.
  final PairingClientState state;

  @override
  Widget build(BuildContext context) {
    final mirroring = state.phase == PairingClientPhase.mirroring;
    return Row(
      key: AppKeys.pairingTabletShell,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: PairingTabletLayout.sidebarWidthFor(context),
          // The sidebar keeps its own Scaffold: the phone page is already a
          // self-contained surface (background, bottom bar), and re-parenting it
          // here rather than re-implementing it is what keeps the two layouts
          // from drifting.
          child: const PairingSessionListPage(embedded: true),
        ),
        SizedBox(
          width: 1,
          child: ColoredBox(color: mobileHairlineColor(context)),
        ),
        Expanded(
          child: mirroring
              ? PairingMirrorPage(
                  // Keyed exactly like the phone shell's mirror: a new mirror
                  // needs a fresh engine, and a reconnect must rebind to the
                  // *new* subscription while `activeCatalogId` is unchanged.
                  key: ValueKey(
                    'mirror-${state.activeCatalogId}-${state.connectGeneration}',
                  ),
                )
              : const PairingNoMirrorPlaceholder(),
        ),
      ],
    );
  }
}

/// The empty right pane: a tablet has room for the list *and* the terminal, so
/// "nothing open yet" has to be a pane rather than a screen. [PairingMirrorPage]
/// is a full-bleed terminal with no empty state of its own.
class PairingNoMirrorPlaceholder extends StatelessWidget {
  const PairingNoMirrorPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Scaffold(
      key: AppKeys.pairingNoMirrorPlaceholder,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.terminal_outlined,
                  size: 34,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                const SizedBox(height: 14),
                Text(
                  l10n.pairingNoTerminalSelected,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.pairingSelectTerminalHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
