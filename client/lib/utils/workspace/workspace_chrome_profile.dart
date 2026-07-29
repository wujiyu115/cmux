import '../../models/workspace.dart';

/// Fixed scope key for personal launch — workspace tabs and routes.
const kSimpleLaunchProfileId = 'simple';

/// Stable workspace scope id for chrome that must not follow compose-landing
/// drafts (right tools, manage panel, automations scope, …).
String workspaceChromeProfileId(Workspace workspace, {String? routeProfileId}) {
  final route = routeProfileId?.trim() ?? '';
  if (route.isNotEmpty) return route;
  final defaultId = workspace.defaultProfileId.trim();
  if (defaultId.isNotEmpty) return defaultId;
  return kSimpleLaunchProfileId;
}
