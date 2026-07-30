import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/home_closed_workspace_entry.dart';
import '../../models/workspace.dart';
import '../../models/workspace_topology.dart';
import '../../services/app/desktop_window_actions.dart';
import '../../services/app/platform_utils.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../theme/workspace_topology_colors.dart';
import '../../widgets/notification/notification_bell_button.dart';
import '../../widgets/team_pilot_brand_logo.dart';
import '../../widgets/window_chrome_controls.dart';
import '../../widgets/window_drag_area.dart';
import '../config/config_workspace.dart';
import '../workspace_shell/workspace_shell_tabs.dart';

/// Height of the Apifox-style workspace title bar.
const double kHomeTitleBarHeight = 58;

@visibleForTesting
IconData workspaceTabTopologyIconData(WorkspaceTopology topology) {
  return switch (topology) {
    WorkspaceTopology.local => Icons.folder_outlined,
    WorkspaceTopology.remote => Icons.cloud_outlined,
    WorkspaceTopology.mixed => Icons.hub_outlined,
  };
}

@visibleForTesting
Color workspaceTabTopologyIconColor({
  required ColorScheme colorScheme,
  required Brightness brightness,
  WorkspaceTopology topology = WorkspaceTopology.local,
  bool active = false,
  bool hovered = false,
}) {
  final base = WorkspaceTopologyColors.of(
    topology: topology,
    colorScheme: colorScheme,
    brightness: brightness,
  );
  final alpha = active ? 1.0 : (hovered ? 0.9 : 0.8);
  return base.withValues(alpha: alpha);
}

@visibleForTesting
String recentlyClosedEntryLabel(HomeClosedWorkspaceEntry entry) {
  final name = entry.displayName.trim();
  return name.isNotEmpty ? name : entry.workspaceId;
}

@visibleForTesting
String? recentlyClosedSubtitleLine({
  required AppLocalizations l10n,
  required HomeClosedWorkspaceEntry entry,
  required List<HomeClosedWorkspaceEntry> entries,
}) {
  final path = entry.primaryPath.trim();
  return path.isNotEmpty ? path : null;
}

@visibleForTesting
WorkspaceTopology? recentlyClosedTopology({
  required HomeClosedWorkspaceEntry entry,
  Workspace? workspace,
}) {
  if (workspace != null) {
    return workspaceTopologyOf(workspace.folders);
  }
  return entry.topology;
}

/// Workspace tab glyph colored by topology (local / remote / mixed).
class WorkspaceTabTopologyIcon extends StatelessWidget {
  const WorkspaceTabTopologyIcon({
    required this.topology,
    required this.colorScheme,
    required this.brightness,
    required this.size,
    this.active = false,
    this.hovered = false,
    super.key,
  });

  final WorkspaceTopology topology;
  final ColorScheme colorScheme;
  final Brightness brightness;
  final double size;
  final bool active;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    return Icon(
      workspaceTabTopologyIconData(topology),
      size: size,
      color: workspaceTabTopologyIconColor(
        colorScheme: colorScheme,
        brightness: brightness,
        topology: topology,
        active: active,
        hovered: hovered,
      ),
    );
  }
}

class HomeTitleBar extends StatefulWidget {
  const HomeTitleBar({
    this.activeTabKey,
    this.pageChrome = WorkspacePageChrome.home,
    this.recentlyClosed = const [],
    this.workspaces = const [],
    this.trailingActions,
    this.onReopenClosedTab,
    super.key,
  });

  /// The workspace tab currently shown, or null when the Home view is shown.
  final String? activeTabKey;

  /// Page backdrop chrome; matches [HomeShell] scaffold fill.
  final WorkspacePageChrome pageChrome;

  /// Recently closed tabs (newest first), excluding currently open ids.
  final List<HomeClosedWorkspaceEntry> recentlyClosed;

  /// Workspace records for resolving topology in the recently-closed menu.
  final List<Workspace> workspaces;

  /// Compact actions on the right (e.g. Run toolbar), before pane toggles.
  final Widget? trailingActions;

  final ValueChanged<String>? onReopenClosedTab;

  @override
  State<HomeTitleBar> createState() => _HomeTitleBarState();
}

class _HomeTitleBarState extends State<HomeTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (!useCustomDesktopWindowTitleBar) return;
    windowManager.addListener(this);
    _syncExpanded();
  }

  @override
  void dispose() {
    if (useCustomDesktopWindowTitleBar) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _syncExpanded() async {
    final expanded = await isDesktopWindowExpanded();
    if (!mounted) return;
    setState(() => _isMaximized = expanded);
  }

  @override
  void onWindowMaximize() => unawaited(_syncExpanded());

  @override
  void onWindowUnmaximize() => unawaited(_syncExpanded());

  @override
  void onWindowEnterFullScreen() => unawaited(_syncExpanded());

  @override
  void onWindowLeaveFullScreen() => unawaited(_syncExpanded());

  Future<void> _toggleMaximize({bool optionPressed = false}) async {
    if (Platform.isMacOS) {
      await handleMacGreenButton(optionPressed: optionPressed);
    } else {
      await toggleDesktopWindowExpand();
    }
    await _syncExpanded();
  }

  Widget _buildWindowControls() {
    return WindowChromeControls(
      height: kHomeTitleBarHeight,
      isMaximized: _isMaximized,
      onMinimize: () => windowManagerCall(windowManager.minimize),
      onToggleMaximize: _toggleMaximize,
      onClose: () => windowManagerCall(windowManager.close),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;
    final showWindowControls = useCustomDesktopWindowTitleBar;

    return Material(
      color: cs.workspacePageChrome(widget.pageChrome),
      child: SizedBox(
        height: kHomeTitleBarHeight,
        child: Row(
          children: [
            SizedBox(width: 8),
            if (showWindowControls && useMacWindowChromeStyle)
              _buildWindowControls(),
            SizedBox(width: useMacWindowChromeStyle ? 8 : 20),
            const _BrandMark(),
            // Home entry lives in the left [WorkspaceNavSidebar] now — the pill
            // here was redundant. Workspace tabs live in the sidebar too; the
            // title bar keeps only the recently-closed overflow and a draggable
            // spacer that absorbs the remaining width (window-move area).
            Expanded(
              child: Row(
                children: [
                  const SizedBox(width: 6),
                  _RecentlyClosedOverflowButton(
                    entries: widget.recentlyClosed,
                    workspaces: widget.workspaces,
                    onReopen: widget.onReopenClosedTab,
                  ),
                  Expanded(
                    child: showWindowControls
                        ? const WindowDragArea(child: SizedBox.expand())
                        : const SizedBox.expand(),
                  ),
                ],
              ),
            ),
            if (widget.trailingActions != null) ...[
              widget.trailingActions!,
              const SizedBox(width: 8),
            ],
            if (widget.activeTabKey != null) ...[
              const WorkspaceShellPaneVisibilityToggles(),
              const SizedBox(width: 4),
            ],
            const SizedBox(width: 8),
            const NotificationBellButton(),
            TpIconButton(
              iconWidget: SvgPicture.asset(
                'assets/icons/settings_gear.svg',
                width: context.tpIconSizes.md,
                height: context.tpIconSizes.md,
                theme: SvgTheme(currentColor: cs.onSurfaceVariant),
              ),
              tooltip: l10n.settings,
              backgroundColor: Colors.transparent,
              onTap: () => showWorkspaceSettingsDialog(context),
            ),
            const SizedBox(width: 10),
            if (showWindowControls && !useMacWindowChromeStyle)
              _buildWindowControls(),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [const TeamPilotBrandLogo()],
    );
  }
}

/// Overflow menu listing recently closed workspace tabs; opens on hover.
class _RecentlyClosedOverflowButton extends StatefulWidget {
  const _RecentlyClosedOverflowButton({
    required this.entries,
    this.workspaces = const [],
    this.onReopen,
  });

  final List<HomeClosedWorkspaceEntry> entries;
  final List<Workspace> workspaces;
  final ValueChanged<String>? onReopen;

  static const _menuMaxHeight = 320.0;
  static const _menuWidth = 300.0;
  static const _closeDelay = Duration(milliseconds: 180);

  @override
  State<_RecentlyClosedOverflowButton> createState() =>
      _RecentlyClosedOverflowButtonState();
}

class _RecentlyClosedOverflowButtonState
    extends State<_RecentlyClosedOverflowButton> {
  final _popoverController = TpPopoverController();
  Timer? _closeTimer;
  var _pointerOnAnchor = false;
  var _pointerOnMenu = false;

  TpActionMenuController get _menuController =>
      TpActionMenuController(_popoverController);

  @override
  void dispose() {
    _closeTimer?.cancel();
    _popoverController.dispose();
    super.dispose();
  }

  void _cancelCloseTimer() {
    _closeTimer?.cancel();
    _closeTimer = null;
  }

  void _scheduleClose() {
    _cancelCloseTimer();
    _closeTimer = Timer(_RecentlyClosedOverflowButton._closeDelay, () {
      if (!_pointerOnAnchor && !_pointerOnMenu && _popoverController.isOpen) {
        _popoverController.hide();
      }
    });
  }

  void _openMenu() {
    _cancelCloseTimer();
    if (!_popoverController.isOpen) {
      _popoverController.show();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final entries = [
      for (final entry in widget.entries)
        if (entry.workspaceId.trim().isNotEmpty) entry,
    ];
    final workspaceById = {
      for (final workspace in widget.workspaces)
        workspace.workspaceId: workspace,
    };

    return TpActionMenuAnchor(
      controller: _popoverController,
      minWidth: _RecentlyClosedOverflowButton._menuWidth,
      fixedPanelWidth: _RecentlyClosedOverflowButton._menuWidth,
      onOpen: _cancelCloseTimer,
      popoverBuilder: (context, controller) => MouseRegion(
        onEnter: (_) {
          _pointerOnMenu = true;
          _cancelCloseTimer();
        },
        onExit: (_) {
          _pointerOnMenu = false;
          _scheduleClose();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text(
                l10n.homeWorkspaceRecentlyClosed,
                style: styles.smSemiboldColored(cs.onSurfaceVariant),
              ),
            ),
            if (entries.isEmpty)
              TpActionMenuItem(
                icon: Icons.inbox_outlined,
                label: l10n.homeWorkspaceRecentlyClosedEmpty,
                enabled: false,
                menuController: _menuController,
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: _RecentlyClosedOverflowButton._menuMaxHeight,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < entries.length; i++) ...[
                        if (i > 0)
                          const SizedBox(
                            height: TpActionMenuMetrics.itemGap,
                          ),
                        _RecentlyClosedMenuItem(
                          entry: entries[i],
                          entries: entries,
                          workspace: workspaceById[entries[i].workspaceId],
                          menuController: _menuController,
                          onReopen: widget.onReopen,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      child: MouseRegion(
        onEnter: (_) {
          _pointerOnAnchor = true;
          _openMenu();
        },
        onExit: (_) {
          _pointerOnAnchor = false;
          _scheduleClose();
        },
        child: TpIconButton(
          icon: Icons.more_horiz,
          tooltip: l10n.homeWorkspaceRecentlyClosed,
          color: cs.onSurfaceVariant,
          backgroundColor: Colors.transparent,
          onTap: null,
        ),
      ),
    );
  }
}

class _RecentlyClosedMenuItem extends StatelessWidget {
  const _RecentlyClosedMenuItem({
    required this.entry,
    required this.entries,
    required this.workspace,
    required this.menuController,
    this.onReopen,
  });

  final HomeClosedWorkspaceEntry entry;
  final List<HomeClosedWorkspaceEntry> entries;
  final Workspace? workspace;
  final TpActionMenuController menuController;
  final ValueChanged<String>? onReopen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final subtitle = recentlyClosedSubtitleLine(
      l10n: l10n,
      entry: entry,
      entries: entries,
    );
    final topology = recentlyClosedTopology(entry: entry, workspace: workspace);
    final brightness = Theme.of(context).brightness;

    return TpActionMenuItem(
      iconWidget: WorkspaceTabTopologyIcon(
        topology: topology ?? WorkspaceTopology.local,
        colorScheme: cs,
        brightness: brightness,
        size: TpActionMenuMetrics.iconSize(context),
      ),
      label: recentlyClosedEntryLabel(entry),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.xsColored(cs.onSurfaceVariant),
            ),
      menuController: menuController,
      onTap: () => onReopen?.call(entry.tabKey),
    );
  }
}