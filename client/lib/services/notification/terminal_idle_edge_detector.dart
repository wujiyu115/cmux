/// Per-pane working→idle edge detection for `TerminalIdleNotificationService`.
///
/// Extracted from the service because the service takes a concrete
/// `WorkspaceTerminalRegistry` (real panes, real PTYs) and so cannot be unit
/// tested; this is the part with all the timing decisions in it.
///
/// Two deliberate delays sit on top of `TerminalActivityTracker`, whose own
/// quiet window is only 2.5s and is shared with boot-frame / inject-readiness
/// logic that must stay fast:
///
/// * [minimumWorkDuration] drops trivially short bursts (a quick `ls`).
/// * [idleGrace] requires the quiet to *hold*. A CLI agent routinely pauses
///   longer than the tracker's 2.5s between tool calls — its spinner paints
///   only block glyphs, which the tracker's fingerprint skips as noise, so a
///   thinking pause is indistinguishable from a finished turn. Without this
///   grace one turn fires several notifications.
class TerminalIdleEdgeDetector {
  TerminalIdleEdgeDetector({
    this.minimumWorkDuration = const Duration(seconds: 5),
    this.idleGrace = const Duration(seconds: 8),
  });

  /// How long a pane must have been busy for its quiet to be worth announcing.
  final Duration minimumWorkDuration;

  /// How long the quiet must hold after the burst ends before notifying.
  final Duration idleGrace;

  final _panes = <String, _PaneEdgeState>{};

  /// Records one tick's observation of [paneId] and returns true when the pane
  /// has just completed a notifiable working → idle transition.
  ///
  /// [reportsAgentStatus] latches: once a pane has reported an agent lifecycle
  /// event, this heuristic stays out of its way for the rest of the pane's life.
  /// The caller's own signal is not sticky — the attention row it reads is
  /// pruned after 30 minutes idle — and un-latching would resume double-firing
  /// on the very panes that already have semantic notifications.
  bool observe({
    required String paneId,
    required bool working,
    required bool reportsAgentStatus,
    required DateTime now,
  }) {
    final pane = _panes.putIfAbsent(paneId, _PaneEdgeState.new);
    if (reportsAgentStatus) pane.agentLatched = true;
    if (pane.agentLatched) {
      // Keep the bookkeeping current so no stale edge surfaces later.
      pane.wasWorking = working;
      pane.workingSince = null;
      pane.idleSince = null;
      return false;
    }

    if (working) {
      if (!pane.wasWorking) pane.workingSince = now;
      // Output resumed: this was a pause inside the turn, not the end of it.
      pane.idleSince = null;
      pane.wasWorking = true;
      return false;
    }

    if (pane.wasWorking) {
      final since = pane.workingSince;
      pane.workingSince = null;
      pane.wasWorking = false;
      final workedLongEnough =
          since != null && now.difference(since) >= minimumWorkDuration;
      // Arm the grace window; never notify on the edge itself.
      pane.idleSince = workedLongEnough ? now : null;
      return false;
    }

    final pending = pane.idleSince;
    if (pending != null && now.difference(pending) >= idleGrace) {
      pane.idleSince = null;
      return true;
    }
    return false;
  }

  /// Drops bookkeeping for panes that no longer exist, which is also what
  /// clears the agent-status latch.
  void retainOnly(Set<String> livePaneIds) =>
      _panes.removeWhere((id, _) => !livePaneIds.contains(id));

  void clear() => _panes.clear();
}

class _PaneEdgeState {
  bool wasWorking = false;
  bool agentLatched = false;

  /// When the idle → working rising edge happened.
  DateTime? workingSince;

  /// When the working → idle falling edge happened, while the grace window for
  /// it is still open. Null when nothing is pending.
  DateTime? idleSince;
}
