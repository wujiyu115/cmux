import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_config_section.dart';

void main() {
  test('manage shows the project-scoped sections', () {
    expect(WorkspaceConfigSection.sections, [
      WorkspaceConfigSection.settings,
    ]);
  });

  test('fromSegment resolves known segments only', () {
    expect(
      WorkspaceConfigSection.fromSegment('settings'),
      WorkspaceConfigSection.settings,
    );
    expect(WorkspaceConfigSection.fromSegment('extensions'), isNull);
    expect(WorkspaceConfigSection.fromSegment('skills'), isNull);
    expect(WorkspaceConfigSection.fromSegment('members'), isNull);
    expect(WorkspaceConfigSection.fromSegment('agent'), isNull);
  });
}
