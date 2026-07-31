import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/workbench/workbench_center_mode.dart';

void main() {
  group('resolveWorkbenchCenterMode', () {
    test('welcome when active is null', () {
      expect(
        resolveWorkbenchCenterMode(activeTabId: null),
        WorkbenchCenterMode.welcome,
      );
    });

    test('tab when active is set', () {
      expect(
        resolveWorkbenchCenterMode(activeTabId: 's1'),
        WorkbenchCenterMode.tab,
      );
    });
  });

  group('kWorkbenchWelcomeCommandIds', () {
    test('exact curated order', () {
      expect(kWorkbenchWelcomeCommandIds, [
        CommandIds.sessionNewTab,
        CommandIds.togglePanel,
        CommandIds.toggleSidebar,
        CommandIds.workspaceSearch,
        CommandIds.showCheatsheet,
      ]);
    });
  });
}
