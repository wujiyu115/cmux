import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_topology.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_title_bar.dart';
import 'package:teampilot/theme/workspace_topology_colors.dart';

void main() {
  late ColorScheme cs;

  setUp(() {
    cs = const ColorScheme.light(
      primary: Color(0xFF0066CC),
      tertiary: Color(0xFFCC6600),
    );
  });

  test('topology tab icons reflect workspace kind', () {
    expect(
      workspaceTabTopologyIconData(WorkspaceTopology.local),
      Icons.folder_outlined,
    );
    expect(
      workspaceTabTopologyIconData(WorkspaceTopology.remote),
      Icons.cloud_outlined,
    );
    expect(
      workspaceTabTopologyIconData(WorkspaceTopology.mixed),
      Icons.hub_outlined,
    );
  });

  test('workspaceTabTopologyIconColor uses toned remote for remote', () {
    final base = WorkspaceTopologyColors.of(
      topology: WorkspaceTopology.remote,
      colorScheme: cs,
      brightness: Brightness.light,
    );
    final color = workspaceTabTopologyIconColor(
      colorScheme: cs,
      brightness: Brightness.light,
      topology: WorkspaceTopology.remote,
    );
    expect(color, base.withValues(alpha: 0.8));
  });

  test('workspaceTabTopologyIconColor uses toned mixed for mixed', () {
    final base = WorkspaceTopologyColors.of(
      topology: WorkspaceTopology.mixed,
      colorScheme: cs,
      brightness: Brightness.dark,
    );
    final color = workspaceTabTopologyIconColor(
      colorScheme: cs,
      brightness: Brightness.dark,
      topology: WorkspaceTopology.mixed,
      active: true,
    );
    expect(color, base.withValues(alpha: 1));
  });
}
