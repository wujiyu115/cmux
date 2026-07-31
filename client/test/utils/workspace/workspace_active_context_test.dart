import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/utils/workspace/workspace_active_context.dart';

void main() {
  test('idle has no session', () {
    expect(WorkspaceActiveContext.idle.activeSessionId, isNull);
  });
}
