import '../../cubits/workbench/workbench_tab.dart';

/// Which shell/run surfaces [WorkbenchBody] should keep mounted.
class WorkbenchBodyKeepAlivePlan {
  const WorkbenchBodyKeepAlivePlan({
    required this.shellSurfaceIds,
    required this.shellActiveSurfaceId,
    required this.shellOffstage,
    required this.runSessionIds,
    required this.active,
  });

  /// Shell surface (split tab) ids in strip order (tabOrder filtered by kind).
  final List<String> shellSurfaceIds;

  /// Surface id passed to the single [WorkspaceTerminalPanel] (needs a valid id
  /// even when offstage).
  final String? shellActiveSurfaceId;

  /// True when the shell surface is mounted but not the active tab.
  final bool shellOffstage;

  /// Run session ids in strip order that are still live in RunCubit.
  final List<String> runSessionIds;

  final WorkbenchTabId? active;

  bool get mountShell => shellSurfaceIds.isNotEmpty;

  bool runOffstage(String sessionId) {
    final a = active;
    return a == null ||
        a.kind != WorkbenchTabKind.run ||
        a.id != sessionId;
  }
}

/// Derive keep-alive mounts from strip order ∩ live domain ids.
WorkbenchBodyKeepAlivePlan resolveWorkbenchBodyKeepAlive({
  required List<WorkbenchTabId> tabOrder,
  required WorkbenchTabId? active,
  required Iterable<String> liveRunSessionIds,
}) {
  final shellSurfaceIds = [
    for (final tab in tabOrder)
      if (tab.kind == WorkbenchTabKind.shell) tab.id,
  ];

  final liveRuns = liveRunSessionIds.toSet();
  final runSessionIds = [
    for (final tab in tabOrder)
      if (tab.kind == WorkbenchTabKind.run && liveRuns.contains(tab.id))
        tab.id,
  ];

  String? shellActiveSurfaceId;
  var shellOffstage = true;
  if (shellSurfaceIds.isNotEmpty) {
    if (active?.kind == WorkbenchTabKind.shell) {
      shellActiveSurfaceId = active!.id;
      shellOffstage = false;
    } else {
      // Panel needs a valid id while offstage; prefer last shell in strip order.
      shellActiveSurfaceId = shellSurfaceIds.last;
      shellOffstage = true;
    }
  }

  return WorkbenchBodyKeepAlivePlan(
    shellSurfaceIds: shellSurfaceIds,
    shellActiveSurfaceId: shellActiveSurfaceId,
    shellOffstage: shellOffstage,
    runSessionIds: runSessionIds,
    active: active,
  );
}
