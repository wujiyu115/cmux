import 'package:flutter/material.dart';

import '../../theme/workspace_surface_layers.dart';

/// Card shell for extension management rows.
class ExtensionManagementCard extends StatelessWidget {
  const ExtensionManagementCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: workspaceCardDecoration(cs, radius: 12),
      child: child,
    );
  }
}
