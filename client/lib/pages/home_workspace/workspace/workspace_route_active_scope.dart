import 'package:flutter/widgets.dart';

import 'workspace_config_section.dart';

/// Foreground/background state for a kept-alive title-bar workspace tab.
///
/// Provided by [_WorkspaceTabSlot] so [WorkspacePage] does not take a
/// [routeActive] constructor arg that changes on every sibling tab switch
/// (which would rebuild the whole subtree).
class WorkspaceRouteActiveScope extends InheritedWidget {
  const WorkspaceRouteActiveScope({
    required this.routeActive,
    this.view,
    this.configSection,
    required super.child,
    super.key,
  });

  final bool routeActive;
  final String? view;
  final WorkspaceConfigSection? configSection;

  static WorkspaceRouteActiveScope? maybeOf(BuildContext context) {
    // `dependOn…`, not `get…`: callers read this from build /
    // didChangeDependencies and rely on being re-run when the slot's active
    // state flips. The bare lookup registered no dependency, so kept-alive
    // tabs never observed their own deactivation/reactivation (stale
    // quick-open / run-command host bindings, dead reactivation syncs).
    return context.dependOnInheritedWidgetOfExactType<
      WorkspaceRouteActiveScope
    >();
  }

  static bool routeActiveOf(BuildContext context) {
    return maybeOf(context)?.routeActive ?? true;
  }

  @override
  bool updateShouldNotify(WorkspaceRouteActiveScope oldWidget) {
    return routeActive != oldWidget.routeActive ||
        view != oldWidget.view ||
        configSection != oldWidget.configSection;
  }
}
