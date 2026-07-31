import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:panes/panes.dart';

import '../../cubits/layout_cubit.dart';
import '../../models/layout_preferences.dart';
import '../../services/workspace/workspace_pane_policy.dart';
import '../../widgets/workspace_terminal_panel.dart';
import 'pane_overlay_host.dart';
import 'workspace_ide_pane_chrome.dart';
import 'workspace_ide_pane_sync.dart';

/// App-owned IDE shell that lays out the workspace as left | center | right,
/// using `panes` as the interaction engine.
///
/// Shell / Run live as center workbench tabs (not a bottom dock).
/// [LayoutCubit] / [LayoutPreferences] stay the sole source of layout intent:
/// the `panes` controllers are derived from prefs on build, and drag-end sizes
/// are committed back through the cubit (never mid-drag — see the design spec's
/// write-back rules). Side panes use [PaneSize.pixel] so hiding them keeps
/// their child `State` mounted (fractional hide disposes children), which
/// protects center agent / shell terminals from teardown when a sibling pane
/// toggles.
class WorkspaceIdeShell extends StatefulWidget {
  const WorkspaceIdeShell({
    required this.center,
    required this.right,
    this.left,
    this.terminalHold,
    super.key,
  });

  /// Optional left pane. Null (the default) removes the left region entirely:
  /// the workspace nav now lives globally and session/worktree actions moved to
  /// the shell "+" menu, so the docked shell is a two-pane center | right.
  final Widget? left;
  final Widget center;
  final Widget right;

  /// Bridge used to bracket PTY resizes of center shell terminals during a
  /// split drag.
  final WorkspaceTerminalHoldHandle? terminalHold;

  @override
  State<WorkspaceIdeShell> createState() => _WorkspaceIdeShellState();
}

class _WorkspaceIdeShellState extends State<WorkspaceIdeShell> {
  static const _leftId = 'left';
  static const _centerId = 'center';
  static const _rightId = 'right';

  late final PaneController _rowController;

  WorkspaceIdePaneSnapshot? _applied;
  bool _syncScheduled = false;
  WorkspaceIdePaneSnapshot? _pending;

  /// Last viewport size from [PaneSizeReporter]; used by [BlocListener] to derive
  /// [WorkspacePanePolicy.effective] before the next layout pass.
  double _viewportWidth = WorkspacePanePolicy.narrowBreakpointWidth;
  double _viewportHeight = 900;

  WorkspaceIdePaneBounds? _appliedBounds;
  bool _boundsSyncScheduled = false;
  WorkspaceIdePaneBounds? _pendingBounds;
  WorkspaceIdePaneSnapshot? _pendingBoundsSnapshot;

  bool _rowResizing = false;

  /// When narrow, the side regions render as overlays (see [PaneOverlayHost]),
  /// so the docked panes render nothing for left/right to avoid double-mounting
  /// the sidebar / right-tools panel. Set each build before the pane builders
  /// run (during layout of the root `MultiPane`).
  bool _narrow = false;

  /// Effective dock flags from the latest viewport measure. Chrome uses
  /// this instead of [PaneController.isVisible] so padding/radius track user
  /// intent immediately — the controller sync is intentionally post-frame.
  WorkspaceIdePaneSnapshot? _layoutSnapshot;

  /// First open skips pane size tweens so sidebar/terminal do not animate
  /// through dozens of layouts on the landing critical path.
  var _paneAnimationEnabled = false;

  bool get _hasLeft => widget.left != null;

  /// Forces the left region off when no [left] pane is supplied, so every
  /// downstream consumer (snapshot dock flags, bounds, chrome insets, overlay)
  /// sees a consistent "no left" policy regardless of `sidebarVisible` intent.
  WorkspacePaneEffective _suppressLeft(WorkspacePaneEffective e) {
    if (_hasLeft) return e;
    return WorkspacePaneEffective(
      isNarrow: e.isNarrow,
      dockLeft: false,
      dockRight: e.dockRight,
      overlayLeft: false,
      overlayRight: e.overlayRight,
    );
  }

  @override
  void initState() {
    super.initState();
    // Seed from compose-aware effective so the first frame matches policy.
    // Seeding only `_applied` (and not PaneEntry.visible) lets `_requestSync`
    // short-circuit while controllers still show persisted right-tools intent.
    final layoutState = context.read<LayoutCubit>().state;
    final prefs = layoutState.preferences;
    final effective = _suppressLeft(
      WorkspacePanePolicy.effective(
        preferences: prefs,
        viewportWidth: WorkspacePanePolicy.narrowBreakpointWidth,
      ),
    );
    _rowController = PaneController(
      entries: [
        PaneEntry(
          id: _leftId,
          visible: effective.dockLeft,
          initialSize: PaneSize.pixel(prefs.sidebarWidth),
          minSize: PaneSize.pixel(LayoutPreferences.minSidebarWidth),
        ),
        PaneEntry(
          id: _centerId,
          initialSize: PaneSize.fraction(1),
          minSize: PaneSize.pixel(LayoutPreferences.minWorkbenchMainWidth),
        ),
        PaneEntry(
          id: _rightId,
          visible: effective.dockRight,
          initialSize: PaneSize.pixel(prefs.rightToolsWidth),
          minSize: PaneSize.pixel(LayoutPreferences.minRightToolsWidth),
        ),
      ],
    )..addListener(_onRowChanged);
    _applied = WorkspaceIdePaneSnapshot.from(
      preferences: prefs,
      effective: effective,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _paneAnimationEnabled) return;
      setState(() => _paneAnimationEnabled = true);
    });
  }

  @override
  void dispose() {
    _rowController.removeListener(_onRowChanged);
    _rowController.dispose();
    super.dispose();
  }

  // --- Drag lifecycle: PTY hold on start, prefs commit on end ---------------

  void _onRowChanged() {
    final resizing = _rowController.isResizing;
    if (resizing == _rowResizing) return;
    _rowResizing = resizing;
    if (resizing) {
      widget.terminalHold?.beginPtyHold();
    } else {
      _commitRowSizes();
      widget.terminalHold?.endPtyHold(flush: true);
    }
  }

  void _commitRowSizes() {
    if (!mounted) return;
    final cubit = context.read<LayoutCubit>();
    final left = _rowController.getVisualPixelSize(_leftId);
    if (left != null) cubit.setSidebarWidth(left);
    final right = _rowController.getVisualPixelSize(_rightId);
    if (right != null) cubit.setRightToolsWidth(right);
  }

  // --- Prefs/effective → controllers ----------------------------------------

  WorkspaceIdePaneSnapshot _snapshotFor(LayoutPreferences preferences) {
    return WorkspaceIdePaneSnapshot.from(
      preferences: preferences,
      effective: _suppressLeft(
        WorkspacePanePolicy.effective(
          preferences: preferences,
          viewportWidth: _viewportWidth,
        ),
      ),
    );
  }

  bool _isDockOnlyChange(WorkspaceIdePaneSnapshot next) {
    final applied = _applied;
    if (applied == null) return false;
    return applied.sidebarWidth == next.sidebarWidth &&
        applied.rightToolsWidth == next.rightToolsWidth &&
        (applied.dockLeft != next.dockLeft ||
            applied.dockRight != next.dockRight ||
            applied.isNarrow != next.isNarrow);
  }

  void _onLayoutPreferencesChanged() {
    if (!mounted) return;
    _requestSync(_snapshotFor(context.read<LayoutCubit>().state.preferences));
  }

  void _onViewportSize(Size size) {
    if (!mounted) return;
    if (size.width == _viewportWidth && size.height == _viewportHeight) {
      return;
    }
    final layoutState = context.read<LayoutCubit>().state;
    final was = _suppressLeft(
      WorkspacePanePolicy.effective(
        preferences: layoutState.preferences,
        viewportWidth: _viewportWidth,
      ),
    );
    _viewportWidth = size.width;
    _viewportHeight = size.height;
    final now = _suppressLeft(
      WorkspacePanePolicy.effective(
        preferences: layoutState.preferences,
        viewportWidth: _viewportWidth,
      ),
    );
    final snapshot = WorkspaceIdePaneSnapshot.from(
      preferences: layoutState.preferences,
      effective: now,
    );
    _layoutSnapshot = snapshot;
    _requestSync(snapshot);
    _requestBoundsSync(snapshot);
    _narrow = now.isNarrow;
    final policyChanged =
        was.isNarrow != now.isNarrow ||
        was.dockLeft != now.dockLeft ||
        was.dockRight != now.dockRight ||
        was.overlayLeft != now.overlayLeft ||
        was.overlayRight != now.overlayRight;
    if (policyChanged) {
      setState(() {});
    }
  }

  void _requestSync(WorkspaceIdePaneSnapshot snapshot) {
    if (_sameAsApplied(snapshot)) return;
    _pending = snapshot;
    if (_rowController.isResizing) {
      _scheduleSyncPostFrame();
      return;
    }
    if (_isDockOnlyChange(snapshot)) {
      _applySnapshot(snapshot);
      _pending = null;
      return;
    }
    _scheduleSyncPostFrame();
  }

  void _scheduleSyncPostFrame() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      final pending = _pending;
      if (!mounted || pending == null || _sameAsApplied(pending)) return;
      if (_rowController.isResizing) {
        _scheduleSyncPostFrame();
        return;
      }
      _applySnapshot(pending);
      _pending = null;
    });
  }

  bool _sameAsApplied(WorkspaceIdePaneSnapshot s) {
    final a = _applied;
    return a != null &&
        a.dockLeft == s.dockLeft &&
        a.dockRight == s.dockRight &&
        a.sidebarWidth == s.sidebarWidth &&
        a.rightToolsWidth == s.rightToolsWidth;
  }

  void _applySnapshot(WorkspaceIdePaneSnapshot s) {
    // Never fight an in-progress drag; the drag-end commit will re-derive.
    if (!_rowController.isResizing) {
      _applyPane(_rowController, _leftId, s.sidebarWidth, visible: s.dockLeft);
      _applyPane(
        _rowController,
        _rightId,
        s.rightToolsWidth,
        visible: s.dockRight,
      );
    }
    _applied = s;
    // Re-apply viewport caps after prefs sizes so a large persisted width cannot
    // crush the main column when the window is narrower than before.
    if (!_rowController.isResizing) {
      _applyPaneBounds(_boundsFor(s), s);
    }
  }

  void _applyPane(
    PaneController controller,
    String id,
    double size, {
    required bool visible,
  }) {
    // ignore: deprecated_member_use
    controller.updateSize(id, PaneSize.pixel(size));
    if (visible) {
      controller.show(id);
    } else {
      controller.hide(id);
    }
  }

  // --- Viewport-derived max sizes (protect main workbench) ------------------

  WorkspaceIdePaneBounds _boundsFor(WorkspaceIdePaneSnapshot snapshot) {
    final available = WorkspaceIdePaneBounds.shellAvailableSize(
      viewportWidth: _viewportWidth,
      viewportHeight: _viewportHeight,
      dockLeft: snapshot.dockLeft,
      dockRight: snapshot.dockRight,
    );
    return WorkspaceIdePaneBounds.compute(
      availableWidth: available.width,
      dockLeft: snapshot.dockLeft,
      dockRight: snapshot.dockRight,
      sidebarWidth: snapshot.sidebarWidth,
      rightToolsWidth: snapshot.rightToolsWidth,
    );
  }

  void _requestBoundsSync(WorkspaceIdePaneSnapshot snapshot) {
    final bounds = _boundsFor(snapshot);
    if (bounds == _appliedBounds && !_needsVisualClamp(bounds, snapshot)) {
      return;
    }
    _pendingBounds = bounds;
    _pendingBoundsSnapshot = snapshot;
    _scheduleBoundsSyncPostFrame();
  }

  bool _needsVisualClamp(
    WorkspaceIdePaneBounds bounds,
    WorkspaceIdePaneSnapshot snapshot,
  ) {
    if (snapshot.dockLeft) {
      final visual = _rowController.getVisualPixelSize(_leftId);
      if (visual != null && visual > bounds.leftMax) return true;
    }
    if (snapshot.dockRight) {
      final visual = _rowController.getVisualPixelSize(_rightId);
      if (visual != null && visual > bounds.rightMax) return true;
    }
    return false;
  }

  void _scheduleBoundsSyncPostFrame() {
    if (_boundsSyncScheduled) return;
    _boundsSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _boundsSyncScheduled = false;
      final bounds = _pendingBounds;
      final snapshot = _pendingBoundsSnapshot;
      if (!mounted || bounds == null || snapshot == null) return;
      if (_rowController.isResizing) {
        _scheduleBoundsSyncPostFrame();
        return;
      }
      _applyPaneBounds(bounds, snapshot);
      _pendingBounds = null;
      _pendingBoundsSnapshot = null;
    });
  }

  void _applyPaneBounds(
    WorkspaceIdePaneBounds bounds,
    WorkspaceIdePaneSnapshot snapshot,
  ) {
    _setPixelPaneMax(_rowController, _leftId, bounds.leftMax);
    _setPixelPaneMax(_rowController, _rightId, bounds.rightMax);
    if (snapshot.dockLeft) {
      _clampVisualPixelSize(_rowController, _leftId, bounds.leftMax);
    }
    if (snapshot.dockRight) {
      _clampVisualPixelSize(_rowController, _rightId, bounds.rightMax);
    }
    _appliedBounds = bounds;
  }

  void _setPixelPaneMax(PaneController controller, String id, double max) {
    final entry = controller.entries.firstWhere((e) => e.id == id);
    final currentMax = switch (entry.maxSize) {
      PaneSizePixel(:final pixels) => pixels,
      _ => null,
    };
    if (currentMax == max) return;
    controller.updatePane(entry.copyWith(maxSize: PaneSize.pixel(max)));
  }

  void _clampVisualPixelSize(
    PaneController controller,
    String id,
    double max,
  ) {
    final visual = controller.getVisualPixelSize(id);
    if (visual == null || visual <= max) return;
    // ignore: deprecated_member_use
    controller.updateSize(id, PaneSize.pixel(max));
  }

  // --- Build ----------------------------------------------------------------

  bool get _leftDocked => _hasLeft && (_layoutSnapshot?.dockLeft ?? false);

  bool get _rightDocked => _layoutSnapshot?.dockRight ?? false;

  static BorderRadius _paneRadiusOnly({
    required bool topLeft,
    required bool bottomLeft,
    required bool topRight,
    required bool bottomRight,
  }) {
    const r = Radius.circular(WorkspaceIdePaneChrome.paneRadius);
    return BorderRadius.only(
      topLeft: topLeft ? r : Radius.zero,
      bottomLeft: bottomLeft ? r : Radius.zero,
      topRight: topRight ? r : Radius.zero,
      bottomRight: bottomRight ? r : Radius.zero,
    );
  }

  Widget _sideChrome({
    required Widget child,
    required bool leadingOuter,
    required bool trailingOuter,
  }) {
    const inset = WorkspaceIdePaneChrome.paneInset;
    return WorkspaceIdePaneChrome(
      padding: EdgeInsets.fromLTRB(
        leadingOuter ? inset : 0,
        inset,
        trailingOuter ? inset : 0,
        inset,
      ),
      borderRadius: _paneRadiusOnly(
        topLeft: leadingOuter,
        bottomLeft: leadingOuter,
        topRight: trailingOuter,
        bottomRight: trailingOuter,
      ),
      child: child,
    );
  }

  Widget _centerChrome() {
    const inset = WorkspaceIdePaneChrome.paneInset;
    return WorkspaceIdePaneChrome(
      padding: EdgeInsets.fromLTRB(
        _leftDocked ? inset : 0,
        inset,
        _rightDocked ? inset : 0,
        inset,
      ),
      borderRadius: _paneRadiusOnly(
        topLeft: _leftDocked,
        bottomLeft: _leftDocked,
        topRight: _rightDocked,
        bottomRight: _rightDocked,
      ),
      child: widget.center,
    );
  }

  Widget _rowPaneBuilder(BuildContext context, String id, double progress) {
    return switch (id) {
      _leftId => !_hasLeft || _narrow
          ? const SizedBox.shrink()
          : !_leftDocked
          ? widget.left!
          : _sideChrome(
              child: widget.left!,
              leadingOuter: true,
              trailingOuter: false,
            ),
      _rightId => _narrow
          ? const SizedBox.shrink()
          : !_rightDocked
          ? widget.right
          : _sideChrome(
              child: widget.right,
              leadingOuter: false,
              trailingOuter: true,
            ),
      _ => _centerChrome(),
    };
  }

  Duration get _paneAnimationDuration => _paneAnimationEnabled
      ? const Duration(milliseconds: 250)
      : Duration.zero;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocListener<LayoutCubit, LayoutState>(
      listenWhen: (a, b) =>
          _relevantPrefsChanged(a.preferences, b.preferences),
      listener: (context, _) => _onLayoutPreferencesChanged(),
      child: BlocBuilder<LayoutCubit, LayoutState>(
        buildWhen: (a, b) =>
            _relevantPrefsChanged(a.preferences, b.preferences),
        builder: (context, layoutState) {
          final effective = _suppressLeft(
            WorkspacePanePolicy.effective(
              preferences: layoutState.preferences,
              viewportWidth: _viewportWidth,
            ),
          );
          final snapshot = WorkspaceIdePaneSnapshot.from(
            preferences: layoutState.preferences,
            effective: effective,
          );
          _layoutSnapshot = snapshot;
          _requestSync(snapshot);
          _requestBoundsSync(snapshot);
          // Set before building `MultiPane`: the pane builders run during the
          // root pane's layout, which is after this synchronous assignment.
          _narrow = effective.isNarrow;
          final prefs = layoutState.preferences;
          // Measure via PaneSizeReporter so center/sidebar BUILD stays in the
          // normal build phase — not nested under LayoutBuilder layout.
          return PaneSizeReporter(
            onSize: _onViewportSize,
            child: PaneTheme(
              data: workspaceIdePaneTheme(cs),
              child: PaneOverlayHost(
                showLeft: effective.overlayLeft,
                showRight: effective.overlayRight,
                leftWidth: prefs.sidebarWidth,
                rightWidth: prefs.rightToolsWidth,
                left: _hasLeft
                    ? WorkspaceIdePaneChrome(child: widget.left!)
                    : null,
                right: WorkspaceIdePaneChrome(child: widget.right),
                onDismissLeft: () =>
                    context.read<LayoutCubit>().setSidebarVisible(false),
                onDismissRight: () =>
                    context.read<LayoutCubit>().setRightToolsVisible(false),
                child: MultiPane(
                  direction: Axis.horizontal,
                  controller: _rowController,
                  animationDuration: _paneAnimationDuration,
                  paneBuilder: _rowPaneBuilder,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  bool _relevantPrefsChanged(LayoutPreferences a, LayoutPreferences b) {
    return a.sidebarVisible != b.sidebarVisible ||
        a.rightToolsVisible != b.rightToolsVisible ||
        a.sidebarWidth != b.sidebarWidth ||
        a.rightToolsWidth != b.rightToolsWidth;
  }
}
