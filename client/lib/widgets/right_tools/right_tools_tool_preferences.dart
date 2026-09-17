import 'package:flutter/foundation.dart';

import '../../models/layout_preferences.dart';

/// Layout fields that affect right-tools panel tabs and disk refresh only.
@immutable
class RightToolsToolPreferences {
  const RightToolsToolPreferences({
    required this.fileTreeVisible,
    required this.gitVisible,
    required this.searchVisible,
  });

  final bool fileTreeVisible;
  final bool gitVisible;
  final bool searchVisible;

  /// True when any right-tools tab needs [RightToolsLifecycleHost].
  ///
  /// Search needs the tools-scope the host publishes; it does not need the
  /// disk watcher / poll ([needsDiskSideEffects]) — it re-lists on demand.
  bool get needsLifecycleHost => fileTreeVisible || gitVisible || searchVisible;

  /// True when file-tree or git panels need disk watchers / refresh.
  bool get needsDiskSideEffects => fileTreeVisible || gitVisible;

  factory RightToolsToolPreferences.from(LayoutPreferences preferences) {
    return RightToolsToolPreferences(
      fileTreeVisible: preferences.fileTreeVisible,
      gitVisible: preferences.gitVisible,
      searchVisible: preferences.searchVisible,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RightToolsToolPreferences &&
            fileTreeVisible == other.fileTreeVisible &&
            gitVisible == other.gitVisible &&
            searchVisible == other.searchVisible;
  }

  @override
  int get hashCode => Object.hash(fileTreeVisible, gitVisible, searchVisible);
}
