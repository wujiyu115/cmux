import 'package:flutter/foundation.dart';

import '../../models/layout_preferences.dart';

/// Layout fields that affect right-tools panel tabs and disk refresh only.
@immutable
class RightToolsToolPreferences {
  const RightToolsToolPreferences({
    required this.fileTreeVisible,
    required this.gitVisible,
  });

  final bool fileTreeVisible;
  final bool gitVisible;

  /// True when any right-tools tab needs [RightToolsLifecycleHost].
  bool get needsLifecycleHost => fileTreeVisible || gitVisible;

  /// True when file-tree or git panels need disk watchers / refresh.
  bool get needsDiskSideEffects => fileTreeVisible || gitVisible;

  factory RightToolsToolPreferences.from(LayoutPreferences preferences) {
    return RightToolsToolPreferences(
      fileTreeVisible: preferences.fileTreeVisible,
      gitVisible: preferences.gitVisible,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RightToolsToolPreferences &&
            fileTreeVisible == other.fileTreeVisible &&
            gitVisible == other.gitVisible;
  }

  @override
  int get hashCode => Object.hash(fileTreeVisible, gitVisible);
}
