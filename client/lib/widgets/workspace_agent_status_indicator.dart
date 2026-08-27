import 'package:flutter/material.dart';

import '../cubits/agent_attention_cubit.dart';
import 'session_working_spinner.dart';

/// Trailing status slot for a workspace nav row. Distinct visuals per
/// [WorkspaceAgentStatus]; renders nothing when idle.
///
/// Colors follow the agent-notice toast variants: working → primary spinner
/// (same as session indicators), waiting → tertiary hand marker (same as
/// session indicators), interrupted → error (warning toast), done → secondary
/// (app success green, success toast).
class WorkspaceAgentStatusIndicator extends StatelessWidget {
  const WorkspaceAgentStatusIndicator({
    super.key,
    required this.status,
    this.size = 13,
  });

  final WorkspaceAgentStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case WorkspaceAgentStatus.none:
        return const SizedBox.shrink();
      case WorkspaceAgentStatus.waiting:
        return SessionWaitingMarker(size: size, color: cs.tertiary);
      case WorkspaceAgentStatus.working:
        return SessionWorkingSpinner(size: size, color: cs.primary);
      case WorkspaceAgentStatus.interrupted:
        return Icon(
          Icons.stop_circle_rounded,
          size: size,
          color: cs.error,
        );
      case WorkspaceAgentStatus.done:
        return Icon(
          Icons.check_circle_rounded,
          size: size,
          color: cs.secondary,
        );
    }
  }
}
