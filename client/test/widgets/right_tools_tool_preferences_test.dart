import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/right_tools/right_tools_tool_preferences.dart';

void main() {
  group('RightToolsToolPreferences', () {
    test('needsLifecycleHost is false when all tabs hidden', () {
      const prefs = RightToolsToolPreferences(
        fileTreeVisible: false,
        gitVisible: false,
      );
      expect(prefs.needsLifecycleHost, isFalse);
      expect(prefs.needsDiskSideEffects, isFalse);
    });

    test('needsDiskSideEffects covers file tree and git', () {
      const fileTree = RightToolsToolPreferences(
        fileTreeVisible: true,
        gitVisible: false,
      );
      expect(fileTree.needsLifecycleHost, isTrue);
      expect(fileTree.needsDiskSideEffects, isTrue);

      const git = RightToolsToolPreferences(
        fileTreeVisible: false,
        gitVisible: true,
      );
      expect(git.needsDiskSideEffects, isTrue);
    });
  });
}
