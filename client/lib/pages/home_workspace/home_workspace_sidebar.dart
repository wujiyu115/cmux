import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/layout_preferences.dart';
import '../../theme/workspace_surface_layers.dart';
import 'home_workspace_library_view.dart';

/// Left rail of the workspace home: library shortcuts mirroring the Apifox
/// sidebar. Shortcuts swap the right pane via [onSelectLibraryView].
class HomeSidebar extends StatelessWidget {
  const HomeSidebar({
    this.activeLibraryView,
    this.allWorkspacesActive = false,
    this.onSelectAllWorkspaces,
    this.onSelectLibraryView,
    super.key,
  });

  final HomeLibraryView? activeLibraryView;
  final bool allWorkspacesActive;
  final VoidCallback? onSelectAllWorkspaces;
  final ValueChanged<HomeLibraryView>? onSelectLibraryView;

  static const double width = LayoutPreferences.defaultHomeSidebarWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final onAllWorkspaces = onSelectAllWorkspaces;
    final onLibrary = onSelectLibraryView;

    return Container(
      decoration: BoxDecoration(
        color: cs.workspaceCard,
        border: Border(
          right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(32, 48, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ShortcutRow(
            icon: Icons.star_outline_rounded,
            label: l10n.homeWorkspaceMyFavorites,
            active: activeLibraryView == HomeLibraryView.favorites,
            onTap: () => onLibrary?.call(HomeLibraryView.favorites),
          ),
          const SizedBox(height: 4),
          _ShortcutRow(
            icon: Icons.history_rounded,
            label: l10n.homeWorkspaceRecentVisits,
            active: activeLibraryView == HomeLibraryView.recent,
            onTap: () => onLibrary?.call(HomeLibraryView.recent),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          _ShortcutRow(
            icon: Icons.folder_copy_outlined,
            label: l10n.homeWorkspaceAllWorkspaces,
            active: allWorkspacesActive,
            onTap: () => onAllWorkspaces?.call(),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _ShortcutRow extends StatefulWidget {
  const _ShortcutRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  State<_ShortcutRow> createState() => _ShortcutRowState();
}

class _ShortcutRowState extends State<_ShortcutRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final active = widget.active;
    final Color fg = active ? cs.primary : cs.onSurface;
    final Color background = active
        ? cs.primary.withValues(alpha: 0.14)
        : _hovered
        ? cs.onSurface.withValues(alpha: 0.05)
        : Colors.transparent;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: context.tpIconSizes.md,
                  color: active ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: active
                      ? styles.lgSemiboldColored(fg)
                      : styles.lgColored(fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
