import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../models/mcp_server.dart';
import 'package:teampilot/theme/workspace_surface_layers.dart';

class TeamMcpRow extends StatelessWidget {
  const TeamMcpRow({
    super.key,
    required this.server,
    required this.assigned,
    required this.onAssignedChanged,
  });

  final McpServer server;
  final bool assigned;
  final ValueChanged<bool> onAssignedChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: workspaceInsetDecoration(cs, radius: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.name,
                    style: TpTextStyles.of(
                      context,
                    ).mdBold,
                  ),
                  Text(
                    server.server['type']?.toString() ?? 'stdio',
                    style: TpTextStyles.of(context).smColored(cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Switch(value: assigned, onChanged: onAssignedChanged),
          ],
        ),
      ),
    );
  }
}
