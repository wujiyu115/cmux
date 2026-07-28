import 'package:flutter/foundation.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:uuid/uuid.dart';

import '../../models/terminal_split.dart';
import '../../models/terminal_surface.dart';
import '../../models/workspace_terminal_session_spec.dart';
import 'terminal_session.dart';
import 'workspace_shell_connector.dart';

const _uuid = Uuid();

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

  int bumpConnectGeneration() => ++connectGeneration;

  void dispose() {
    bumpConnectGeneration();
    session.sshMemberSession?.close();
    session.disconnect();
    session.dispose();
    controller.dispose();
  }
}

/// One workspace's IDEA-style terminal tabs.
///
/// Panes (one [WorkspaceTerminalEntry] each; `entry.id` IS the paneId) live in a
/// flat insertion-ordered store. Layout lives in [_surfaces]: each surface is a
/// tab holding a split tree over pane ids. [activeId] is derived from the active
/// surface's focused pane — there is no standalone active-id field.
class WorkspaceTerminalGroup extends ChangeNotifier {
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
    return WorkspaceTerminalEntry(
      id: _uuid.v4(),
      cwd: cwd,
      spec: spec,
      session: session,
      followWorkspace: followWorkspace,
    )..titleLabel = titleLabel;
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
  final Map<String, WorkspaceTerminalGroup> _groups = {};

  WorkspaceTerminalGroup groupFor(String workspaceId) =>
      _groups.putIfAbsent(workspaceId, WorkspaceTerminalGroup.new);

  void disposeWorkspace(String workspaceId) {
    _groups.remove(workspaceId)?.dispose();
  }

  void disposeAll() {
    for (final g in _groups.values) {
      g.dispose();
    }
    _groups.clear();
  }
}
