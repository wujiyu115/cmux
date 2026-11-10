import 'package:flutter/foundation.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../../models/pane_mode.dart';
import '../../models/terminal_split.dart';
import '../../models/workspace_terminal_session_spec.dart';
import 'workspace_shell_connector.dart';
import 'workspace_terminal_connect_coordinator.dart';
import 'workspace_terminal_registry.dart';

/// Line to type into a freshly created pane, or null when there is nothing to
/// start (a terminal pane, or a chat pane configured with no command).
///
/// A trailing newline submits it. Kept pure so the "which panes start an agent"
/// rule is testable without a PTY.
String? chatAgentLaunchLine({required PaneMode mode, required String command}) {
  if (mode != PaneMode.chat) return null;
  final trimmed = command.trim();
  if (trimmed.isEmpty) return null;
  return '$trimmed\r';
}

/// How often (and how long) to wait for a chat pane's PTY before giving up on
/// typing the agent command into it.
const _chatAgentReadyPoll = Duration(milliseconds: 50);
const _chatAgentReadyTimeout = Duration(seconds: 20);

/// Shared create+connect path for workspace terminal tabs (panel + Run inject).
class WorkspaceTerminalSessionOps {
  /// Creates a session, adds a group entry, and connects the transport.
  Future<WorkspaceTerminalEntry> openEntry({
    required WorkspaceTerminalGroup group,
    required WorkspaceShellConnector connector,
    required WorkspaceTerminalConnectCoordinator connectCoordinator,
    required String cwd,
    required WorkspaceTerminalSessionSpec spec,
    required TerminalTheme theme,
    required String sshConnectFailedMessage,
    required bool select,
    String titleLabel = '',
    bool followWorkspace = false,
    PaneMode mode = PaneMode.terminal,
    String chatAgentCommand = '',
    VoidCallback? onStateChanged,
    bool Function()? mounted,
  }) async {
    final session = connector.createSession(spec);
    final label = titleLabel.isNotEmpty
        ? titleLabel
        : await connector.labelForSpec(spec);
    final entry = group.addEntry(
      cwd: cwd,
      spec: spec,
      session: session,
      select: select,
      titleLabel: label,
      followWorkspace: followWorkspace,
      mode: mode,
    );
    await connectEntry(
      group: group,
      entry: entry,
      connectCoordinator: connectCoordinator,
      theme: theme,
      sshConnectFailedMessage: sshConnectFailedMessage,
      onStateChanged: onStateChanged,
      mounted: mounted,
    );
    await startChatAgent(
      entry: entry,
      chatAgentCommand: chatAgentCommand,
      mounted: mounted,
    );
    return entry;
  }

  /// Creates a session and adds it as a **new pane inside an existing surface**
  /// (splitting [anchorPaneId], default the surface's focused pane, along
  /// [axis]), then connects the transport. Mirrors [openEntry]'s connect / error
  /// handling. Returns the created entry, or `null` when [surfaceId] is unknown
  /// (no session is created in that case).
  Future<WorkspaceTerminalEntry?> openPaneInSurface({
    required WorkspaceTerminalGroup group,
    required WorkspaceShellConnector connector,
    required WorkspaceTerminalConnectCoordinator connectCoordinator,
    required String surfaceId,
    required String cwd,
    required WorkspaceTerminalSessionSpec spec,
    required TerminalTheme theme,
    required String sshConnectFailedMessage,
    SplitAxis axis = SplitAxis.vertical,
    String? anchorPaneId,
    String titleLabel = '',
    bool followWorkspace = false,
    PaneMode mode = PaneMode.terminal,
    String chatAgentCommand = '',
    VoidCallback? onStateChanged,
    bool Function()? mounted,
  }) async {
    if (group.surfaceById(surfaceId) == null) return null;
    final session = connector.createSession(spec);
    final label = titleLabel.isNotEmpty
        ? titleLabel
        : await connector.labelForSpec(spec);
    final entry = group.addPaneToSurface(
      surfaceId: surfaceId,
      axis: axis,
      cwd: cwd,
      spec: spec,
      session: session,
      anchorPaneId: anchorPaneId,
      titleLabel: label,
      followWorkspace: followWorkspace,
      mode: mode,
    );
    await connectEntry(
      group: group,
      entry: entry,
      connectCoordinator: connectCoordinator,
      theme: theme,
      sshConnectFailedMessage: sshConnectFailedMessage,
      onStateChanged: onStateChanged,
      mounted: mounted,
    );
    await startChatAgent(
      entry: entry,
      chatAgentCommand: chatAgentCommand,
      mounted: mounted,
    );
    return entry;
  }

  /// Types the configured agent command into a chat pane, once its PTY is up.
  ///
  /// This is the one place the app starts an agent for the user. It is a plain
  /// line written to the pane's own shell rather than a managed subprocess:
  /// nothing about the CLI's protocol is wired in, and the terminal view stays
  /// available precisely so the user can interrupt, answer a permission prompt,
  /// or run something else.
  ///
  /// No-op for [PaneMode.terminal] panes and for an empty command (a chat pane
  /// with nothing to run shows why instead of guessing an agent).
  Future<void> startChatAgent({
    required WorkspaceTerminalEntry entry,
    required String chatAgentCommand,
    bool Function()? mounted,
  }) async {
    final line = chatAgentLaunchLine(
      mode: entry.mode,
      command: chatAgentCommand,
    );
    if (line == null) return;
    final alive = () => !entry.session.isDisposed && (mounted?.call() ?? true);
    if (!alive()) return;
    // `connect` returns as soon as the transport exists; bytes written before
    // the PTY is ready for IO are dropped, so wait for it. A local shell is up
    // in a tick; an SSH one may take seconds.
    for (var waited = Duration.zero;
        !entry.session.transportReadyForIo;
        waited += _chatAgentReadyPoll) {
      if (waited >= _chatAgentReadyTimeout || !alive()) return;
      await Future<void>.delayed(_chatAgentReadyPoll);
    }
    if (!alive()) return;
    // The shell owns the process from here: no PTY plumbing, no protocol.
    entry.session.input.writeToPty(line);
  }

  /// Connects an existing entry (select / cwd sync / SSH reconnect).
  Future<void> connectEntry({
    required WorkspaceTerminalGroup group,
    required WorkspaceTerminalEntry entry,
    required WorkspaceTerminalConnectCoordinator connectCoordinator,
    required TerminalTheme theme,
    required String sshConnectFailedMessage,
    VoidCallback? onStateChanged,
    bool Function()? mounted,
  }) {
    return connectCoordinator.connect(
      group: group,
      entry: entry,
      theme: theme,
      sshConnectFailedMessage: sshConnectFailedMessage,
      onStateChanged: onStateChanged ?? () {},
      mounted: mounted ?? () => true,
    );
  }
}
