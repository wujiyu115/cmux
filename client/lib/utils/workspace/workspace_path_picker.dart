import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/runtime_target.dart';
import '../../services/storage/app_storage.dart';
import '../../widgets/fuzzy_directory_picker_dialog.dart';
import '../../widgets/remote_directory_browser_dialog.dart';

/// Picks a directory path for a workspace, routed by [targetId]:
///
/// - `ssh:*` and `wsl:*` targets resolve a non-local filesystem, so they open
///   the [RemoteDirectoryBrowserDialog] (with a hand-fill fallback). For WSL
///   this backs onto the distro's `WslFilesystem`.
/// - local targets open the fuzzy-searching [FuzzyDirectoryPickerDialog]
///   (started at the default workspace parent); the native desktop picker
///   remains the fallback when the fuzzy dialog cannot list a filesystem.
Future<String?> pickWorkspaceDirectoryPath(
  BuildContext context, {
  required String targetId,
}) async {
  if (runtimeKindOfId(targetId) != RuntimeKind.local) {
    return showDialog<String>(
      context: context,
      builder: (_) => RemoteDirectoryBrowserDialog(targetId: targetId),
    );
  }
  final defaultParent = await DefaultWorkspaceDirectory.resolveOrNull();
  final picked = await showFuzzyDirectoryPickerDialog(
    context,
    targetId: targetId,
    initialPath: defaultParent,
  );
  if (picked != null) return picked;
  return FilePicker.platform.getDirectoryPath();
}
