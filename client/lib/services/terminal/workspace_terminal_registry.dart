import 'package:flutter/foundation.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:uuid/uuid.dart';

import '../../models/terminal_split.dart';
import '../../models/terminal_surface.dart';
import '../../models/workspace_terminal_session_spec.dart';
import '../../pages/home_workspace/home_workspace_route.dart';
import 'command_log_sink.dart';
import 'shell_command_tracker.dart';
import 'terminal_osc_notification_bridge.dart';
import 'terminal_session.dart';
import 'workspace_shell_connector.dart';

const _uuid = Uuid();

/// Builds the OSC-notification bridge for one pane. Injected so tests can pass
/// a recorder-free stub instead of touching the global notification recorder.
typedef TerminalNotificationBridgeFactory =
    TerminalOscNotificationBridge Function({
      required String Function() attribution,
      required String Function() payload,
    });

TerminalOscNotificationBridge _defaultNotificationBridge({
  required String Function() attribution,
  required String Function() payload,
}) => TerminalOscNotificationBridge(attribution: attribution, payload: payload);

/// Builds the command-log tracker for one pane. Injected so tests can observe
/// rows without installing a global [CommandLogSink].
typedef ShellCommandTrackerFactory =
    ShellCommandTracker Function({
      required String paneId,
      required String workspaceId,
      required PaneLogContext Function() context,
    });

ShellCommandTracker _defaultCommandTracker({
  required String paneId,
  required String workspaceId,
  required PaneLogContext Function() context,
}) => ShellCommandTracker(
  paneId: paneId,
  workspaceId: workspaceId,
  context: context,
  // Resolved per row: the cubit installs itself once the app shell is up.
  onCompleted: (entry) => CommandLogSink.maybeCurrent?.record(entry),
);

/// A single workspace-terminal tab: spec, cwd, session, and view controller.
class WorkspaceTerminalEntry {
  WorkspaceTerminalEntry({
    required this.id,
    required this.cwd,
    required this.spec,
    required this.session,
    this.followWorkspace = false,
  }) : controller = TerminalController();

  final String id;
  String cwd;
  WorkspaceTerminalSessionSpec spec;
  TerminalSession session;

  /// When true, cwd changes re-resolve [spec] via [defaultSessionSpecFor].
  bool followWorkspace;

  bool connected = false;
  int connectGeneration = 0;
  final TerminalController controller;

  /// Cached display label from [WorkspaceShellConnector.labelForSpec].
  String titleLabel = '';

  /// OSC 9/99/777 → notification center, bound for this pane's session.
  TerminalOscNotificationBridge? notificationBridge;

  /// OSC 133 → command log, bound for this pane's session.
  ShellCommandTracker? commandTracker;

  /// Run once when the pane is disposed (pane close, surface close, workspace
  /// close).
  ///
  /// The agent-status seat is released here and not only from the PTY exit
  /// callback: `TerminalLaunchController` skips `onProcessExited` entirely on a
  /// non-zero exit and clears it outright in `disconnect()`, so Ctrl+C, a crash,
  /// or a manual disconnect would otherwise leak the seat.
  VoidCallback? onDisposed;

  int bumpConnectGeneration() => ++connectGeneration;

  void dispose() {
    bumpConnectGeneration();
    notificationBridge?.dispose();
    notificationBridge = null;
    commandTracker?.dispose();
    commandTracker = null;
    session.sshMemberSession?.close();
    session.disconnect();
    session.dispose();
    controller.dispose();
    // Cleared before invoking so a re-entrant dispose cannot double-fire.
    final callback = onDisposed;
    onDisposed = null;
    callback?.call();
  }
}

/// One workspace's IDEA-style terminal tabs.
///
/// Panes (one [WorkspaceTerminalEntry] each; `entry.id` IS the paneId) live in a
/// flat insertion-ordered store. Layout lives in [_surfaces]: each surface is a
/// tab holding a split tree over pane ids. [activeId] is derived from the active
/// surface's focused pane — there is no standalone active-id field.
class WorkspaceTerminalGroup extends ChangeNotifier {
  WorkspaceTerminalGroup({
    this.workspaceId = '',
    String Function()? workspaceLabel,
    TerminalNotificationBridgeFactory? notificationBridgeFactory,
    ShellCommandTrackerFactory? commandTrackerFactory,
  }) : _workspaceLabel = workspaceLabel ?? _noLabel,
       _bridgeFactory = notificationBridgeFactory,
       _trackerFactory = commandTrackerFactory;

  static String _noLabel() => '';

  /// Owning workspace tab id; empty in tests that build a bare group.
  final String workspaceId;

  /// Workspace display name, resolved lazily (workspaces load asynchronously).
  final String Function() _workspaceLabel;

  /// Null disables terminal notifications for this group entirely.
  final TerminalNotificationBridgeFactory? _bridgeFactory;

  /// Null disables command logging for this group entirely.
  final ShellCommandTrackerFactory? _trackerFactory;

  final List<WorkspaceTerminalEntry> _entries = [];
  final List<TerminalSurface> _surfaces = [];
  String? _activeSurfaceId;

  /// Focused pane of the active surface, or null when there are no surfaces.
  String? get activeId => activeSurface?.focusedPaneId;

  /// Focuses [id]'s pane and activates its surface. Null / unknown id → no-op;
  /// notifies only when something actually changed.
  set activeId(String? id) {
    if (activeId == id) return;
    if (id == null) return;
    final surface = surfaceForPane(id);
    if (surface == null) return;
    final surfaceChanged = _activeSurfaceId != surface.id;
    final focusChanged = surface.focusedPaneId != id;
    _activeSurfaceId = surface.id;
    if (focusChanged) _replaceSurface(surface.copyWith(focusedPaneId: id));
    if (surfaceChanged || focusChanged) notifyListeners();
  }

  /// Unmodifiable view of the flat pane list, in insertion order.
  List<WorkspaceTerminalEntry> get entries => List.unmodifiable(_entries);

  bool contains(String id) => _entries.any((e) => e.id == id);

  WorkspaceTerminalEntry? entryById(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  WorkspaceTerminalEntry? get activeEntry {
    final id = activeId;
    if (id == null) return null;
    return entryById(id);
  }

  // --- Surfaces (split tabs) -------------------------------------------------

  /// Unmodifiable view of the surfaces (tabs), in insertion order.
  List<TerminalSurface> get surfaces => List.unmodifiable(_surfaces);

  String? get activeSurfaceId => _activeSurfaceId;

  set activeSurfaceId(String? id) {
    if (_activeSurfaceId == id) return;
    if (id != null && surfaceById(id) == null) return;
    _activeSurfaceId = id;
    notifyListeners();
  }

  TerminalSurface? get activeSurface {
    final id = _activeSurfaceId;
    if (id == null) return null;
    return surfaceById(id);
  }

  TerminalSurface? surfaceById(String id) {
    for (final s in _surfaces) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The surface whose tree contains [paneId], or null.
  TerminalSurface? surfaceForPane(String paneId) {
    for (final s in _surfaces) {
      if (containsPane(s.root, paneId)) return s;
    }
    return null;
  }

  /// Replaces a surface by id and notifies. Unknown id → no-op. The split view
  /// calls this to write back a dragged ratio or a new tree.
  void updateSurface(TerminalSurface surface) {
    if (_replaceSurface(surface)) notifyListeners();
  }

  // --- Pane lifecycle --------------------------------------------------------

  WorkspaceTerminalEntry addEntry({
    required String cwd,
    required WorkspaceTerminalSessionSpec spec,
    required TerminalSession session,
    required bool select,
    String titleLabel = '',
    bool followWorkspace = false,
  }) {
    final entry = _newEntry(
      cwd: cwd,
      spec: spec,
      session: session,
      titleLabel: titleLabel,
      followWorkspace: followWorkspace,
    );
    _entries.add(entry);
    final surface = TerminalSurface.single(
      id: _uuid.v4(),
      name: titleLabel,
      paneId: entry.id,
    );
    _surfaces.add(surface);
    if (select) _activeSurfaceId = surface.id;
    notifyListeners();
    return entry;
  }

  /// Splits [anchorPaneId] (default: the surface's focused pane) along [axis],
  /// puts the new pane in `second`, focuses it, and returns its entry. Throws
  /// [StateError] on unknown [surfaceId].
  WorkspaceTerminalEntry addPaneToSurface({
    required String surfaceId,
    required SplitAxis axis,
    required String cwd,
    required WorkspaceTerminalSessionSpec spec,
    required TerminalSession session,
    String? anchorPaneId,
    String titleLabel = '',
    bool followWorkspace = false,
  }) {
    final surface = surfaceById(surfaceId);
    if (surface == null) {
      throw StateError('Unknown surfaceId: $surfaceId');
    }
    final entry = _newEntry(
      cwd: cwd,
      spec: spec,
      session: session,
      titleLabel: titleLabel,
      followWorkspace: followWorkspace,
    );
    _entries.add(entry);
    final anchor = anchorPaneId ?? surface.focusedPaneId;
    final newRoot = splitLeaf(surface.root, anchor, axis, entry.id);
    _replaceSurface(surface.copyWith(root: newRoot, focusedPaneId: entry.id));
    notifyListeners();
    return entry;
  }

  bool removeEntry(String id) {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index < 0) return _entries.isEmpty;
    final surface = surfaceForPane(id);
    final surfaceIndex = surface == null ? -1 : _surfaces.indexOf(surface);
    final wasActiveSurface = surface != null && surface.id == _activeSurfaceId;
    if (surface != null) {
      if (surface.paneIds.length <= 1) {
        _surfaces.removeAt(surfaceIndex);
      } else {
        _replaceSurface(surface.withPaneRemoved(id));
      }
    }
    _entries[index].dispose();
    _entries.removeAt(index);
    if (_surfaces.isEmpty) {
      _activeSurfaceId = null;
      notifyListeners();
      return true;
    }
    if (wasActiveSurface) {
      final next = surfaceIndex >= _surfaces.length
          ? _surfaces.length - 1
          : surfaceIndex;
      _activeSurfaceId = _surfaces[next].id;
    }
    notifyListeners();
    return false;
  }

  /// Closes an entire surface (tab): disposes every pane it holds, removes the
  /// surface, and migrates [_activeSurfaceId] to a neighbour. Unknown id → the
  /// current emptiness state. Returns whether the group is now empty.
  bool removeSurface(String surfaceId) {
    final surfaceIndex = _surfaces.indexWhere((s) => s.id == surfaceId);
    if (surfaceIndex < 0) return _surfaces.isEmpty;
    final surface = _surfaces[surfaceIndex];
    final wasActive = surface.id == _activeSurfaceId;
    for (final paneId in surface.paneIds) {
      final index = _entries.indexWhere((e) => e.id == paneId);
      if (index < 0) continue;
      _entries[index].dispose();
      _entries.removeAt(index);
    }
    _surfaces.removeAt(surfaceIndex);
    if (_surfaces.isEmpty) {
      _activeSurfaceId = null;
      notifyListeners();
      return true;
    }
    if (wasActive) {
      final next = surfaceIndex >= _surfaces.length
          ? _surfaces.length - 1
          : surfaceIndex;
      _activeSurfaceId = _surfaces[next].id;
    }
    notifyListeners();
    return false;
  }

  // --- Focus / zoom / rename -------------------------------------------------

  /// Moves focus to the next pane in the active surface (wrap-around).
  void focusNextPane() => _moveFocus(nextLeaf);

  /// Moves focus to the previous pane in the active surface (wrap-around).
  void focusPrevPane() => _moveFocus(prevLeaf);

  /// Toggles the zoomed (maximized) pane on the active surface. [paneId]
  /// defaults to the surface's focused pane.
  void toggleZoom([String? paneId]) {
    final surface = activeSurface;
    if (surface == null) return;
    final target = paneId ?? surface.focusedPaneId;
    if (!containsPane(surface.root, target)) return;
    if (surface.zoomedPaneId == target) {
      _replaceSurface(surface.copyWith(clearZoom: true));
    } else {
      _replaceSurface(surface.copyWith(zoomedPaneId: target));
    }
    notifyListeners();
  }

  /// Sets [paneId]'s custom name in its owning surface; empty [name] clears it.
  void renamePane(String paneId, String name) {
    final surface = surfaceForPane(paneId);
    if (surface == null) return;
    final names = Map<String, String>.from(surface.paneNames);
    if (name.isEmpty) {
      names.remove(paneId);
    } else {
      names[paneId] = name;
    }
    _replaceSurface(surface.copyWith(paneNames: names));
    notifyListeners();
  }

  /// Renames a surface (tab). Unknown [surfaceId] → no-op.
  void renameSurface(String surfaceId, String name) {
    final surface = surfaceById(surfaceId);
    if (surface == null) return;
    _replaceSurface(surface.copyWith(name: name));
    notifyListeners();
  }

  /// False when the group holds exactly one pane in total (the last pane cannot
  /// be closed).
  bool get canCloseActivePane => _entries.length > 1;

  @override
  void dispose() {
    for (final e in _entries) {
      e.dispose();
    }
    _entries.clear();
    _surfaces.clear();
    _activeSurfaceId = null;
    super.dispose();
  }

  // --- internals -------------------------------------------------------------

  WorkspaceTerminalEntry _newEntry({
    required String cwd,
    required WorkspaceTerminalSessionSpec spec,
    required TerminalSession session,
    required String titleLabel,
    required bool followWorkspace,
  }) {
    final entry = WorkspaceTerminalEntry(
      id: _uuid.v4(),
      cwd: cwd,
      spec: spec,
      session: session,
      followWorkspace: followWorkspace,
    )..titleLabel = titleLabel;
    final factory = _bridgeFactory;
    if (factory != null) {
      final bridge = factory(
        attribution: () => paneAttribution(entry.id),
        // Deep-link to this pane's shell tab so notification taps land on the
        // right terminal even when the workspace holds several.
        payload: () => workspaceId.isEmpty
            ? ''
            : HomeWorkspaceRoute.paneLocation(
                workspaceId: workspaceId,
                paneId: entry.id,
              ),
      );
      entry.notificationBridge = bridge;
      session.bindOscNotifications(bridge);
    }
    final trackerFactory = _trackerFactory;
    if (trackerFactory != null) {
      final tracker = trackerFactory(
        paneId: entry.id,
        workspaceId: workspaceId,
        context: () => paneLogContext(entry.id),
      );
      entry.commandTracker = tracker;
      session.bindCommandTracker(tracker);
    }
    return entry;
  }

  /// Mutable pane facts a logged command should carry: surface, labels, cwd.
  @visibleForTesting
  PaneLogContext paneLogContext(String paneId) {
    final surface = surfaceForPane(paneId);
    final entry = entryById(paneId);
    return PaneLogContext(
      surfaceId: surface?.id ?? '',
      surfaceName: surface?.name ?? '',
      paneName: surface?.paneNames[paneId] ?? entry?.titleLabel ?? '',
      workspaceName: _workspaceLabel().trim(),
      workingDirectory: entry?.cwd ?? '',
    );
  }

  /// `workspace · pane` label for notifications raised by [paneId]. Falls back
  /// to whichever half is known; empty when neither is.
  String paneAttribution(String paneId) {
    final surface = surfaceForPane(paneId);
    final paneName =
        surface?.paneNames[paneId] ?? entryById(paneId)?.titleLabel ?? '';
    return [
      if (_workspaceLabel().trim().isNotEmpty) _workspaceLabel().trim(),
      if (paneName.trim().isNotEmpty) paneName.trim(),
    ].join(' · ');
  }

  /// Swaps a surface into the list by id (no notify). Returns whether it hit.
  bool _replaceSurface(TerminalSurface surface) {
    final idx = _surfaces.indexWhere((s) => s.id == surface.id);
    if (idx < 0) return false;
    _surfaces[idx] = surface;
    return true;
  }

  void _moveFocus(String? Function(SplitNode, String) step) {
    final surface = activeSurface;
    if (surface == null) return;
    final next = step(surface.root, surface.focusedPaneId);
    if (next == null || next == surface.focusedPaneId) return;
    _replaceSurface(surface.copyWith(focusedPaneId: next));
    notifyListeners();
  }
}

/// Owns workspace-terminal groups keyed by workspace tab id.
class WorkspaceTerminalRegistry {
  WorkspaceTerminalRegistry({
    TerminalNotificationBridgeFactory? notificationBridgeFactory =
        _defaultNotificationBridge,
    ShellCommandTrackerFactory? commandTrackerFactory = _defaultCommandTracker,
  }) : _bridgeFactory = notificationBridgeFactory,
       _trackerFactory = commandTrackerFactory;

  final Map<String, WorkspaceTerminalGroup> _groups = {};
  final TerminalNotificationBridgeFactory? _bridgeFactory;
  final ShellCommandTrackerFactory? _trackerFactory;
  final _RegistryChanges _changes = _RegistryChanges();

  /// Fires whenever panes/surfaces churn in any group, or a group is added or
  /// removed. Lets the pairing catalog re-emit `session.changed` when terminals
  /// open or close. Registry outlives its listeners (app-lifetime singleton).
  Listenable get changes => _changes;

  /// Live view of all currently-tracked workspace groups. Used by the
  /// terminal-idle notifier to poll pane activity across every workspace.
  Iterable<WorkspaceTerminalGroup> get groups => _groups.values;

  /// The group and entry owning [paneId], or null when no pane matches.
  ///
  /// Non-creating on purpose — unlike [groupFor], which inserts an empty group
  /// as a side effect. Used to map an agent-status seat (`ws:<paneId>`) back to
  /// its workspace for notification attribution and foreground suppression.
  (WorkspaceTerminalGroup, WorkspaceTerminalEntry)? locatePane(String paneId) {
    final id = paneId.trim();
    if (id.isEmpty) return null;
    for (final group in _groups.values) {
      final entry = group.entryById(id);
      if (entry != null) return (group, entry);
    }
    return null;
  }

  /// Resolves a workspace's display name for notification attribution. Set once
  /// the workspace store exists; until then notifications carry the pane label
  /// only.
  String Function(String workspaceId)? workspaceLabelResolver;

  WorkspaceTerminalGroup groupFor(String workspaceId) =>
      _groups.putIfAbsent(workspaceId, () {
        final group = WorkspaceTerminalGroup(
          workspaceId: workspaceId,
          workspaceLabel: () => workspaceLabelResolver?.call(workspaceId) ?? '',
          notificationBridgeFactory: _bridgeFactory,
          commandTrackerFactory: _trackerFactory,
        );
        group.addListener(_changes.notify);
        _changes.notify();
        return group;
      });

  void disposeWorkspace(String workspaceId) {
    final group = _groups.remove(workspaceId);
    if (group == null) return;
    group.removeListener(_changes.notify);
    group.dispose();
    _changes.notify();
  }

  void disposeAll() {
    for (final g in _groups.values) {
      g.removeListener(_changes.notify);
      g.dispose();
    }
    _groups.clear();
    _changes.notify();
  }
}

/// Public-notify wrapper: [ChangeNotifier.notifyListeners] is protected, so the
/// registry forwards group churn through this instead of subclassing.
class _RegistryChanges extends ChangeNotifier {
  void notify() => notifyListeners();
}
