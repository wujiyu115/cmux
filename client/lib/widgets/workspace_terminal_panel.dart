import 'dart:async';
import 'package:shared_ui/shared_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_alacritty/input/paste.dart' as alacritty_paste;
import 'package:flutter_alacritty/input/term_mode.dart' show anyMouse;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/chat_cubit.dart';
import '../cubits/command_log_cubit.dart';
import '../cubits/layout_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/runtime_target.dart';
import '../models/terminal_split.dart';
import '../models/terminal_surface.dart';
import '../models/workspace_folder.dart';
import '../models/workspace_terminal_session_spec.dart';
import '../pages/command_log/command_log_dialog.dart';
import '../services/commands/command_bus.dart';
import '../services/commands/terminal_split_command_registrar.dart';
import '../services/selection_ai/selection_ai_context.dart';
import '../services/selection_ai/selection_ai_menu_specs.dart';
import '../services/selection_ai/selection_ask_ai.dart';
import '../services/selection_ai/selection_ask_ai_fab_host.dart';
import '../services/ssh/ssh_profile_connection_coordinator.dart';
import '../services/terminal/terminal_layout_coordinator.dart';
// Prefixed so the host's `applyLayoutPreset` method does not shadow the
// top-level `applyLayoutPreset` function this file also calls.
import '../services/terminal/terminal_layout_presets.dart' as layout_presets;
import '../services/terminal/terminal_theme_mapper.dart';
import '../services/terminal/terminal_uri_opener.dart';
import '../services/host/host_interactive_shell.dart';
import '../services/terminal/workspace_shell_connector.dart';
import '../services/terminal/workspace_terminal_connect_coordinator.dart';
import '../services/terminal/workspace_terminal_registry.dart';
import '../services/terminal/workspace_terminal_session_ops.dart';
import '../services/workspace/workspace_tools_scope.dart';
import '../theme/workspace_surface_layers.dart';
import '../utils/ui/app_keys.dart';
import 'terminal/terminal_layout_toolbar.dart';
import 'terminal/terminal_pane_keys.dart';
import 'terminal/terminal_split_view.dart';
import 'workspace_terminal/workspace_terminal_body_kind.dart';
import 'workspace_terminal/workspace_terminal_empty_pane.dart';
import 'workspace_terminal/workspace_terminal_view.dart';

/// Debug label for the workspace panel's stable [GlobalKey<TerminalViewState>].
const String kWorkspaceTerminalViewDebugLabel = 'workspace-terminal-view';

/// Lets an outer layout host (e.g. `WorkspaceIdeShell`) bracket PTY resizes of
/// the workspace terminal while a split divider is dragged, without exposing the
/// panel's private [TerminalLayoutCoordinator].
///
/// The panel binds itself on mount and unbinds on dispose; calls before the
/// terminal view registers (or after dispose) are safe no-ops.
class WorkspaceTerminalHoldHandle {
  _WorkspaceTerminalPanelState? _state;

  void _bind(_WorkspaceTerminalPanelState state) => _state = state;

  void _unbind(_WorkspaceTerminalPanelState state) {
    if (identical(_state, state)) _state = null;
  }

  /// Begin holding PTY resizes for the bound terminal (drag start).
  void beginPtyHold() => _state?._beginExternalHold();

  /// End the hold, flushing the final grid to the PTY when [flush] (drag end).
  void endPtyHold({bool flush = true}) => _state?._endExternalHold(flush: flush);

  /// Selects [entryId] as the active terminal tab (no-op if unbound / unknown).
  void selectEntry(String entryId) {
    final state = _state;
    if (state == null) return;
    if (state._group.entryById(entryId) == null) return;
    state._selectEntry(entryId);
  }

  /// Requests keyboard focus on the bound Terminal view (post-frame).
  void requestFocus() => _state?._refocusTerminal();
}

/// IntelliJ-style bottom panel: tab row + shell PTY (not chat agent terminals).
class WorkspaceTerminalPanel extends StatefulWidget {
  const WorkspaceTerminalPanel({
    required this.workspaceId,
    required this.workingDirectory,
    this.holdHandle,
    this.showChrome = true,
    this.onRequestNewTerminal,
    this.activeEntryId,
    super.key,
  });

  final String workspaceId;
  final String workingDirectory;

  /// Optional hold bridge so a split-drag in an outer shell can suppress PTY
  /// SIGWINCH thrash across the drag (forwarded to [TerminalLayoutCoordinator]).
  final WorkspaceTerminalHoldHandle? holdHandle;

  /// When false (unified bottom dock), the panel is body-only — no tab strip.
  final bool showChrome;

  /// Empty-launcher CTA; defaults to starting a local shell when null.
  final VoidCallback? onRequestNewTerminal;

  /// When set (unified dock), body follows this entry instead of [group.activeId].
  final String? activeEntryId;

  @override
  State<WorkspaceTerminalPanel> createState() => _WorkspaceTerminalPanelState();
}

class _WorkspaceTerminalPanelState extends State<WorkspaceTerminalPanel>
    implements TerminalSplitCommandHost {
  WorkspaceTerminalRegistry get _registry =>
      context.read<WorkspaceTerminalRegistry>();
  WorkspaceShellConnector get _connector =>
      context.read<WorkspaceShellConnector>();
  WorkspaceTerminalGroup get _group => _registry.groupFor(widget.workspaceId);

  WorkspaceTerminalConnectCoordinator? _connectCoordinator;
  final _sessionOps = WorkspaceTerminalSessionOps();

  var _bootstrapped = false;
  var _sshReconnectHooked = false;
  StreamSubscription<String>? _sshReconnectSub;

  final _paneKeys = TerminalPaneKeys();

  TerminalLayoutCoordinator? _coordinator;
  final Map<TerminalViewState, PtyResizeHoldTarget> _registeredHoldTargets = {};
  var _registrationScheduled = false;
  final Map<String, int> _lastTerminalThemeFingerprintByEntry = {};
  final _menuOpen = ValueNotifier(false);

  /// Split/focus/layout commands are claimed while this panel's subtree holds
  /// focus (several panels are alive offstage; only the focused one wins the
  /// single-handler-per-id [CommandBus]). Disposer unregisters our handlers.
  CommandBus? _splitCommandBus;
  VoidCallback? _splitCommandsDisposer;

  List<WorkspaceFolder> get _folders =>
      WorkspaceToolsScope.maybeOf(context)?.effectiveFolders ?? const [];

  WorkspaceTerminalConnectCoordinator get _connect => _connectCoordinator ??=
      WorkspaceTerminalConnectCoordinator(connector: _connector);

  @override
  void initState() {
    super.initState();
    widget.holdHandle?._bind(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_sshReconnectHooked) {
      _sshReconnectHooked = true;
      _sshReconnectSub = context
          .read<SshProfileConnectionCoordinator>()
          .sessionReconnectSignals
          .listen(_onSshReconnectSignal);
    }
    if (_bootstrapped) return;
    _bootstrapped = true;
    // Lazy start (Orca-style): never spawn a default shell on mount. Only
    // re-attach engines for sessions that already exist in the registry.
    _reattachExistingEngines();
  }

  @override
  void didUpdateWidget(WorkspaceTerminalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.holdHandle, widget.holdHandle)) {
      oldWidget.holdHandle?._unbind(this);
      widget.holdHandle?._bind(this);
    }
    if (oldWidget.workingDirectory != widget.workingDirectory ||
        oldWidget.workspaceId != widget.workspaceId) {
      _syncActiveEntryCwd();
    }
  }

  /// Drag-start hook from an outer split host: hold PTY resizes for this panel's
  /// terminal view(s). No-op until a terminal view has registered.
  void _beginExternalHold() => _coordinator?.beginAllTransactions();

  /// Drag-end hook: release the hold, flushing the final grid to the PTY.
  void _endExternalHold({bool flush = true}) =>
      _coordinator?.endAllTransactions(flush: flush);

  @override
  void dispose() {
    widget.holdHandle?._unbind(this);
    _splitCommandsDisposer?.call();
    _splitCommandsDisposer = null;
    unawaited(_sshReconnectSub?.cancel());
    for (final target in _registeredHoldTargets.values) {
      _coordinator?.unregister(target);
    }
    _registeredHoldTargets.clear();
    _coordinator?.dispose();
    _menuOpen.dispose();
    super.dispose();
  }

  WorkspaceTerminalEntry? get _activeEntry {
    final forced = widget.activeEntryId?.trim();
    if (forced != null && forced.isNotEmpty) {
      return _group.entryById(forced);
    }
    return _group.activeEntry;
  }

  WorkspaceTerminalSessionSpec _defaultSpec(String cwd) =>
      defaultSessionSpecFor(
        cwd: cwd,
        folders: _folders,
        fallbackLocalShell: HostInteractiveShell.defaultExecutable(),
      );

  void _reattachExistingEngines() {
    if (_group.entries.isEmpty) return;
    for (final entry in _group.entries) {
      if (entry.connected && entry.controller.engine == null) {
        entry.controller.attach(entry.session.engine);
      }
    }
    if (mounted) setState(() {});
  }

  void _syncActiveEntryCwd() {
    final cwd = widget.workingDirectory.trim();
    if (cwd.isEmpty) return;
    final active = _activeEntry;
    // No auto-create when the tab is empty — wait for New terminal / Run inject.
    if (active == null) return;
    unawaited(_syncEntryWithWorkspace(active, cwd));
  }

  Future<void> _syncEntryWithWorkspace(
    WorkspaceTerminalEntry entry,
    String cwd,
  ) async {
    if (!entry.followWorkspace) {
      if (entry.cwd == cwd) return;
      entry.cwd = cwd;
      entry.connected = false;
      await _runConnect(entry);
      if (mounted) setState(() {});
      return;
    }

    final newSpec = _defaultSpec(cwd);
    final specChanged = newSpec != entry.spec;
    final cwdChanged = entry.cwd != cwd;
    if (!specChanged && !cwdChanged) return;

    entry.cwd = cwd;
    entry.bumpConnectGeneration();

    if (specChanged) {
      entry.session.dispose();
      entry.spec = newSpec;
      entry.session = _connector.createSession(newSpec);
      entry.titleLabel = await _connector.labelForSpec(newSpec);
      entry.controller.attach(entry.session.engine);
      entry.connected = false;
    } else {
      entry.connected = false;
    }

    await _runConnect(entry);
    if (mounted) setState(() {});
  }

  Future<void> _addEntry({
    required String cwd,
    required WorkspaceTerminalSessionSpec spec,
    required bool select,
    bool followWorkspace = false,
  }) async {
    await _sessionOps.openEntry(
      group: _group,
      connector: _connector,
      connectCoordinator: _connect,
      cwd: cwd,
      spec: spec,
      theme: _terminalTheme(context),
      sshConnectFailedMessage: context.l10n.workspaceTerminalSshConnectFailed,
      select: select,
      followWorkspace: followWorkspace,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
      mounted: () => mounted,
    );
    if (mounted) setState(() {});
  }

  Future<void> _runConnect(WorkspaceTerminalEntry entry) async {
    await _sessionOps.connectEntry(
      group: _group,
      entry: entry,
      connectCoordinator: _connect,
      theme: _terminalTheme(context),
      sshConnectFailedMessage: context.l10n.workspaceTerminalSshConnectFailed,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
      mounted: () => mounted,
    );
  }

  void _onSshReconnectSignal(String profileId) {
    for (final entry in _group.entries) {
      final target = _connector.runtimeTargetFor(entry.spec);
      if (target.kind != RuntimeKind.ssh) continue;
      final pid = target.sshProfileId ?? sshProfileIdOfId(target.id);
      if (pid != profileId) continue;
      if (!entry.connected && !entry.session.isRunning) continue;
      entry.connected = false;
      entry.session.sshMemberSession?.close();
      entry.session.disconnect();
      if (!mounted) return;
      unawaited(_runConnect(entry));
    }
  }

  void _selectEntry(String id) {
    _group.activeId = id;
    final entry = _group.entryById(id);
    if (entry != null &&
        !entry.connected &&
        entry.cwd.trim().isNotEmpty &&
        !entry.session.isDisposed) {
      unawaited(_runConnect(entry));
    }
    setState(() {});
  }

  TerminalTheme _terminalTheme(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mode = context.select<LayoutCubit, String>(
      (cubit) => cubit.state.preferences.terminalThemeMode,
    );
    final useCustomColors = context.select<LayoutCubit, bool>(
      (cubit) => cubit.state.preferences.useCustomTerminalColors,
    );
    final colorOverrides = context.select<LayoutCubit, Map<String, int>>(
      (cubit) => cubit.state.preferences.terminalColorOverrides,
    );
    return teampilotTerminalTheme(
      cs,
      isDark: isDark,
      mode: mode,
      chrome: WorkspacePageChrome.workspace,
      useCustomColors: useCustomColors,
      colorOverrides: colorOverrides,
    );
  }

  /// Keeps shell PTY engines aligned with [ChatWorkbench] terminal theming.
  void _syncTerminalThemes(TerminalTheme theme) {
    final fp = terminalThemeFingerprint(theme);
    final liveIds = <String>{};
    for (final entry in _group.entries) {
      liveIds.add(entry.id);
      if (entry.session.isDisposed) continue;
      if (_lastTerminalThemeFingerprintByEntry[entry.id] == fp) continue;
      entry.session.applyTerminalTheme(theme);
      _lastTerminalThemeFingerprintByEntry[entry.id] = fp;
    }
    _lastTerminalThemeFingerprintByEntry.removeWhere(
      (id, _) => !liveIds.contains(id),
    );
  }

  /// Diffs the registered hold targets against the currently-mounted pane
  /// states so every pane (including offstage/zoomed-away ones) is held during
  /// a divider drag.
  void _syncTerminalViewRegistration() {
    final coordinator = _coordinator ??= TerminalLayoutCoordinator();
    final live = _paneKeys.mountedStates.toSet();
    final gone =
        _registeredHoldTargets.keys.where((s) => !live.contains(s)).toList();
    for (final state in gone) {
      final target = _registeredHoldTargets.remove(state);
      if (target != null) coordinator.unregister(target);
    }
    for (final state in live) {
      if (_registeredHoldTargets.containsKey(state)) continue;
      final target = ptyHoldTargetFor(state);
      coordinator.register(target);
      _registeredHoldTargets[state] = target;
    }
  }

  void _scheduleTerminalViewRegistration() {
    if (_registrationScheduled) return;
    _registrationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registrationScheduled = false;
      if (mounted) _syncTerminalViewRegistration();
    });
  }

  void _refocusTerminal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final id = _group.activeId;
      if (id == null) return;
      _paneKeys.stateFor(id)?.requestTerminalFocus();
    });
  }

  Future<void> _showContextMenu(
    BuildContext menuContext,
    WorkspaceTerminalEntry entry,
    Offset globalPosition,
    CellOffset? cellOffset,
  ) async {
    final mloc = MaterialLocalizations.of(menuContext);
    final hasSelection = entry.controller.selectionActive;
    final selectionText = entry.controller.readSelectionText() ?? '';
    final aiContext = buildTerminalAiContextClipboardText(
      surfaceLabel: 'workspace-shell',
      text: selectionText,
    );
    final hasAi = aiContext.isNotEmpty;
    final mouseReporting = anyMouse(entry.session.engine.grid.modeFlags);
    final linkUri = cellOffset != null
        ? entry.session.engine.hyperlinkAt(cellOffset.row, cellOffset.column)
        : null;
    final specs = <TpActionMenuSpec>[
      if (linkUri != null)
        TpActionMenuSpec.item(
          value: 'openLink',
          icon: Icons.link,
          label: context.l10n.terminalOpenLink,
        ),
      if (linkUri != null) const TpActionMenuSpec.divider(),
      TpActionMenuSpec.item(
        value: 'paste',
        icon: Icons.content_paste,
        label: mloc.pasteButtonLabel,
      ),
      TpActionMenuSpec.item(
        value: 'copy',
        icon: Icons.content_copy,
        label: (!hasSelection && mouseReporting)
            ? menuContext.l10n.terminalCopySelectHint
            : mloc.copyButtonLabel,
        enabled: hasSelection,
      ),
      ...selectionAiMenuSpecs(
        l10n: menuContext.l10n,
        copyEnabled: hasAi,
        askAiEnabled: hasAi,
        onCopyAsAiContext: () {
          unawaited(Clipboard.setData(ClipboardData(text: aiContext)));
        },
        onAskAi: () {
          unawaited(_openAskAi(aiContext));
        },
      ),
      TpActionMenuSpec.item(
        value: 'selectAll',
        icon: Icons.select_all,
        label: mloc.selectAllButtonLabel,
      ),
    ];

    String? selected;
    _menuOpen.value = true;
    try {
      selected = await showTpActionMenuFromSpecs<String>(
        context: menuContext,
        globalPosition: globalPosition,
        popUpAnimationStyle: const AnimationStyle(duration: Duration.zero),
        specs: specs,
      );
    } finally {
      if (mounted) _menuOpen.value = false;
    }
    if (!menuContext.mounted) return;
    _refocusTerminal();
    switch (selected) {
      case 'openLink':
        if (linkUri != null) {
          await TerminalUriOpener.open(linkUri, workingDirectory: entry.cwd);
        }
      case 'paste':
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text;
        if (text != null && text.isNotEmpty) {
          entry.controller.onTerminalInputStart();
          entry.session.engine.write(
            alacritty_paste.pasteBytes(
              text,
              modeFlags: entry.session.engine.grid.modeFlags,
            ),
          );
          entry.controller.clearSelection();
        }
      case 'copy':
        final text = entry.controller.readSelectionText();
        if (text != null && text.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: text));
        }
      case 'selectAll':
        final grid = entry.session.engine.grid;
        if (grid.rows > 0 && grid.columns > 0) {
          entry.controller.selectionStart(0, 0, false, 0);
          entry.controller.selectionUpdate(
            grid.rows - 1,
            grid.columns - 1,
            false,
          );
        }
      default:
        break;
    }
  }

  Future<void> _openAskAi(String aiContext) {
    if (aiContext.trim().isEmpty || !mounted) return Future.value();
    for (final workspace in context.read<ChatCubit>().state.workspaces) {
      if (workspace.workspaceId != widget.workspaceId) continue;
      return SelectionAskAi.openComposeDialog(
        context,
        aiContext: aiContext,
        workspace: workspace,
        tabScopeId: widget.workspaceId,
      );
    }
    return Future.value();
  }

  void _startDefaultTerminal() {
    final dir = widget.workingDirectory.trim();
    if (dir.isEmpty) return;
    unawaited(
      _addEntry(
        cwd: dir,
        spec: _defaultSpec(dir),
        followWorkspace: true,
        select: true,
      ),
    );
  }

  void _onEmptyNewTerminal() {
    final custom = widget.onRequestNewTerminal;
    if (custom != null) {
      custom();
      return;
    }
    _startDefaultTerminal();
  }

  /// Split-toolbar row above the active surface. Shown regardless of
  /// [WorkspaceTerminalPanel.showChrome] (the real hosts pass `false`).
  Widget _buildLayoutToolbar(TerminalSurface surface) {
    return TerminalLayoutToolbar(
      onSplitRight: () =>
          unawaited(_splitActiveSurface(SplitAxis.vertical)),
      onSplitDown: () =>
          unawaited(_splitActiveSurface(SplitAxis.horizontal)),
      onApplyPreset: (preset) => unawaited(_applyLayoutPreset(preset)),
      onEqualize: _equalizeActiveSurface,
      onToggleZoom: () {
        _group.toggleZoom();
        if (mounted) setState(() {});
      },
      onClosePane: _closeActivePane,
      onShowCommandLog: showCommandLog,
      isZoomed: surface.zoomedPaneId != null,
      canClosePane: _group.canCloseActivePane,
    );
  }

  /// Resolves the cwd a new split pane inherits from the currently focused
  /// pane, falling back to the workspace working directory. Mirrors how the
  /// new-terminal path resolves cwd.
  String _cwdForNewPane() {
    final focused = _activeEntry?.cwd.trim();
    if (focused != null && focused.isNotEmpty) return focused;
    return widget.workingDirectory.trim();
  }

  /// Splits the active surface along [axis] (vertical = split right, horizontal
  /// = split down), anchored on the focused pane. No-op without an active
  /// surface or a resolvable cwd. Returns the new entry, or null.
  Future<WorkspaceTerminalEntry?> _splitActiveSurface(SplitAxis axis) async {
    final surface = _group.activeSurface;
    if (surface == null) return null;
    final cwd = _cwdForNewPane();
    if (cwd.isEmpty) return null;
    final entry = await _sessionOps.openPaneInSurface(
      group: _group,
      connector: _connector,
      connectCoordinator: _connect,
      surfaceId: surface.id,
      axis: axis,
      anchorPaneId: _group.activeId,
      cwd: cwd,
      spec: _defaultSpec(cwd),
      theme: _terminalTheme(context),
      sshConnectFailedMessage: context.l10n.workspaceTerminalSshConnectFailed,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
      mounted: () => mounted,
    );
    if (mounted) setState(() {});
    return entry;
  }

  /// Rebuilds the active surface into [preset]'s shape, spawning any deficit
  /// panes first (sequentially, so ids are deterministic). Lossless: no live
  /// pane is destroyed.
  Future<void> _applyLayoutPreset(
    layout_presets.TerminalLayoutPreset preset,
  ) async {
    final initial = _group.activeSurface;
    if (initial == null) return;
    final deficit =
        layout_presets.presetSlotCount(preset) - initial.paneIds.length;
    for (var i = 0; i < deficit; i++) {
      await _splitActiveSurface(SplitAxis.vertical);
      if (!mounted) return;
    }
    final surface = _group.activeSurface;
    if (surface == null) return;
    final surfaceId = surface.id;
    void apply() {
      final s = _group.surfaceById(surfaceId);
      if (s == null) return;
      _group.updateSurface(
        layout_presets.applyLayoutPreset(s, preset, paneIds: s.paneIds),
      );
    }

    final coordinator = _coordinator;
    if (coordinator != null) {
      await coordinator.runLayoutTransaction(() async => apply());
    } else {
      apply();
    }
    if (mounted) setState(() {});
  }

  /// Resets every split ratio on the active surface to 0.5.
  void _equalizeActiveSurface() {
    final surface = _group.activeSurface;
    if (surface == null) return;
    final surfaceId = surface.id;
    void apply() {
      final s = _group.surfaceById(surfaceId);
      if (s == null) return;
      _group.updateSurface(s.copyWith(root: equalize(s.root)));
    }

    final coordinator = _coordinator;
    if (coordinator != null) {
      coordinator.runLayoutTransactionSync(apply);
    } else {
      apply();
    }
    if (mounted) setState(() {});
  }

  /// Closes the focused pane via the group's single removal path. No-op when
  /// the group holds its last pane.
  void _closeActivePane() {
    if (!_group.canCloseActivePane) return;
    final id = _group.activeId;
    if (id == null) return;
    _group.removeEntry(id);
    if (mounted) setState(() {});
  }

  /// Claims the terminal split/focus/layout commands for this panel when its
  /// subtree gains focus. Re-registering fresh handlers (disposing the previous
  /// claim first) makes the focused panel win the single-handler-per-id bus,
  /// even after another panel had claimed the ids.
  void _claimSplitCommands() {
    final bus = _splitCommandBus ??= context.read<CommandBus>();
    _splitCommandsDisposer?.call();
    _splitCommandsDisposer = registerTerminalSplitCommands(bus, this);
  }

  @override
  void splitRight() => unawaited(_splitActiveSurface(SplitAxis.vertical));

  @override
  void splitDown() => unawaited(_splitActiveSurface(SplitAxis.horizontal));

  @override
  void focusNextPane() {
    final surface = _group.activeSurface;
    if (surface == null) return;
    final target = nextLeaf(surface.root, surface.focusedPaneId);
    if (target != null) _selectEntry(target);
  }

  @override
  void focusPrevPane() {
    final surface = _group.activeSurface;
    if (surface == null) return;
    final target = prevLeaf(surface.root, surface.focusedPaneId);
    if (target != null) _selectEntry(target);
  }

  @override
  void focusPaneInDirection(PaneDirection direction) {
    final surface = _group.activeSurface;
    final activeId = _group.activeId;
    if (surface == null || activeId == null) return;
    final target = paneInDirection(surface.root, activeId, direction);
    if (target != null) _selectEntry(target);
  }

  @override
  void toggleZoom() {
    if (_group.activeSurface == null) return;
    _group.toggleZoom();
    if (mounted) setState(() {});
  }

  @override
  void equalizePanes() => _equalizeActiveSurface();

  @override
  void closeActivePane() => _closeActivePane();

  @override
  void applyLayoutPreset(layout_presets.TerminalLayoutPreset preset) =>
      unawaited(_applyLayoutPreset(preset));

  /// Opens the command log window. Insert / run target the focused pane's PTY
  /// through the session's existing input controller — no new write path.
  @override
  void showCommandLog() {
    unawaited(
      showCommandLogDialog(
        context,
        cubit: context.read<CommandLogCubit>(),
        onInsert: (command) => _writeToActivePane(command, submit: false),
        onRun: (command) => _writeToActivePane(command, submit: true),
      ),
    );
  }

  /// Writes [command] to the focused pane, with a trailing `\r` when [submit].
  void _writeToActivePane(String command, {required bool submit}) {
    final entry = _activeEntry;
    if (entry == null || !entry.session.transportReadyForIo) return;
    entry.session.input.writeToPty(submit ? '$command\r' : command);
    _refocusTerminal();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cwd = widget.workingDirectory.trim();
    final active = _activeEntry;
    final theme = _terminalTheme(context);
    _syncTerminalThemes(theme);
    final terminalBackground = Color(0xFF000000 | theme.background);
    final terminalForeground = Color(0xFF000000 | theme.foreground);
    final bodyKind = resolveWorkspaceTerminalBodyKind(
      workingDirectory: cwd,
      hasActiveEntry: active != null,
    );

    final Widget terminalBody;
    switch (bodyKind) {
      case WorkspaceTerminalBodyKind.noWorkingDirectory:
        terminalBody = Center(
          child: Text(
            l10n.workspaceTerminalNoWorkingDirectory,
            style: TpTextStyles.of(context).smColored(
              terminalForeground.withValues(alpha: 0.65),
            ),
          ),
        );
      case WorkspaceTerminalBodyKind.emptyLauncher:
        terminalBody = WorkspaceTerminalEmptyPane(
          foreground: terminalForeground,
          onNewTerminal: _onEmptyNewTerminal,
        );
      case WorkspaceTerminalBodyKind.activeSession:
        _paneKeys.prune(_group.entries.map((e) => e.id).toSet());
        final surface =
            _group.surfaceForPane(active!.id) ?? _group.activeSurface;
        if (surface == null) {
          terminalBody = const SizedBox.shrink();
          break;
        }
        final splitView = TerminalSplitView(
          surface: surface,
          paneKeys: _paneKeys,
          coordinator: _coordinator ??= TerminalLayoutCoordinator(),
          focusBorderColor: Theme.of(context).colorScheme.primary,
          paneBuilder: (paneContext, paneId, key, isFocused) {
            final entry = _group.entryById(paneId);
            if (entry == null) return const SizedBox.shrink();
            return WorkspaceTerminalView(
              entry: entry,
              theme: theme,
              terminalViewKey: key,
              siblings: _group.entries,
              workspaceId: widget.workspaceId,
              onContextMenu: (position, cell) =>
                  _showContextMenu(context, entry, position, cell),
            );
          },
          onSurfaceChanged: (s) => _group.updateSurface(s),
          // Every pointer-down in a pane reports focus; skip the rebuild when
          // that pane already has it.
          onPaneFocused: (paneId) {
            if (_group.activeId == paneId) return;
            _selectEntry(paneId);
          },
        );
        final fabWrappedSplitView = ValueListenableBuilder<bool>(
          valueListenable: _menuOpen,
          child: splitView,
          builder: (context, menuOpen, child) {
            return SelectionAskAiFabHost(
              listenable: active.controller,
              selectionActive: () => active.controller.selectionActive,
              readAiContext: () => buildTerminalAiContextClipboardText(
                surfaceLabel: 'workspace-shell',
                text: active.controller.readSelectionText() ?? '',
              ),
              onAskAi: _openAskAi,
              menuOpen: menuOpen,
              child: child!,
            );
          },
        );
        terminalBody = Column(
          children: [
            _buildLayoutToolbar(surface),
            const TpSeparator(),
            Expanded(child: fabWrappedSplitView),
          ],
        );
    }

    if (bodyKind == WorkspaceTerminalBodyKind.activeSession &&
        cwd.isNotEmpty) {
      _scheduleTerminalViewRegistration();
    }

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus) _claimSplitCommands();
      },
      child: ColoredBox(
        key: AppKeys.workspaceTerminalPanel,
        color: terminalBackground,
        child: terminalBody,
      ),
    );
  }
}
