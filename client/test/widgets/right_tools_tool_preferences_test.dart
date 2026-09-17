import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/right_tools/right_tools_tool_preferences.dart';

void main() {
  group('RightToolsToolPreferences', () {
    test('needsLifecycleHost is false when all tabs hidden', () {
      const prefs = RightToolsToolPreferences(
        fileTreeVisible: false,
        gitVisible: false,
        searchVisible: false,
      );
      expect(prefs.needsLifecycleHost, isFalse);
      expect(prefs.needsDiskSideEffects, isFalse);
    });

    test('needsDiskSideEffects covers file tree and git', () {
      const fileTree = RightToolsToolPreferences(
        fileTreeVisible: true,
        gitVisible: false,
        searchVisible: false,
      );
      expect(fileTree.needsLifecycleHost, isTrue);
      expect(fileTree.needsDiskSideEffects, isTrue);

      const git = RightToolsToolPreferences(
        fileTreeVisible: false,
        gitVisible: true,
        searchVisible: false,
      );
      expect(git.needsDiskSideEffects, isTrue);
    });

    test('search needs the lifecycle host but not disk side effects', () {
      const search = RightToolsToolPreferences(
        fileTreeVisible: false,
        gitVisible: false,
        searchVisible: true,
      );
      expect(search.needsLifecycleHost, isTrue);
      expect(search.needsDiskSideEffects, isFalse);
    });
  });
}
