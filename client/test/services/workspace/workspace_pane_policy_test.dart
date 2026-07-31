import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/services/workspace/workspace_pane_policy.dart';

void main() {
  const prefs = LayoutPreferences(
    sidebarVisible: true,
    rightToolsVisible: true,
  );

  test('wide docks all intent-visible panes', () {
    final e = WorkspacePanePolicy.effective(
      preferences: prefs,
      viewportWidth: 1200,
    );
    expect(e.isNarrow, isFalse);
    expect(e.dockLeft, isTrue);
    expect(e.dockRight, isTrue);
    expect(e.overlayLeft, isFalse);
    expect(e.overlayRight, isFalse);
  });

  test('narrow undocks sides; intent keeps overlay eligibility', () {
    final e = WorkspacePanePolicy.effective(
      preferences: prefs,
      viewportWidth: 700,
    );
    expect(e.isNarrow, isTrue);
    expect(e.dockLeft, isFalse);
    expect(e.dockRight, isFalse);
    expect(e.overlayLeft, isTrue);
    expect(e.overlayRight, isTrue);
  });

  test('narrow + hidden intent → no overlay eligibility', () {
    final e = WorkspacePanePolicy.effective(
      preferences: prefs.copyWith(
        sidebarVisible: false,
        rightToolsVisible: false,
      ),
      viewportWidth: 700,
    );
    expect(e.overlayLeft, isFalse);
    expect(e.overlayRight, isFalse);
  });
}
