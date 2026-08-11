import 'session_catalog.dart';

/// One workspace as advertised by `workspace.list`, produced host-side by
/// enumerating the on-disk workspace index. Its live terminal panes are *not*
/// carried here — the handler merges those from the [SessionCatalog] at
/// `workspace.list` time, so a workspace with nothing running still lists.
class PairingWorkspaceInfo {
  const PairingWorkspaceInfo({
    required this.workspaceId,
    required this.title,
    this.groupId = '',
  });

  final String workspaceId;
  final String title;

  /// Id of the workspace group this belongs to; empty string = ungrouped.
  final String groupId;
}

/// One workspace group as advertised by the extended `workspace.list`, produced
/// host-side from the desktop's group index. Lets the phone render workspaces
/// folded by group and offer them as targets when creating a workspace.
class PairingGroupInfo {
  const PairingGroupInfo({
    required this.id,
    required this.name,
    required this.order,
  });

  final String id;
  final String name;
  final int order;
}

/// One remote-directory listing for `fs.browse`: [path] is the directory just
/// listed, [parent] its parent (null at a root the browser won't ascend past),
/// and [dirs] the child directory names (dotfiles already filtered host-side).
class PairingDirListing {
  const PairingDirListing({
    required this.path,
    required this.parent,
    required this.dirs,
  });

  final String path;
  final String? parent;
  final List<String> dirs;
}

/// A client's request for a mirrorable terminal in [workspaceId]. [paneId] names
/// a specific pane the phone saw; when it is null or no longer alive the host
/// opens the workspace's default terminal instead.
class PairingActivationRequest {
  const PairingActivationRequest({required this.workspaceId, this.paneId});

  final String workspaceId;
  final String? paneId;
}

/// Outcome of a host-side activation: the [catalogId] the client should then
/// `terminal.subscribe` to. [fallback] is true when the requested pane was gone
/// and the host opened a fresh terminal instead.
class PairingActivationResult {
  const PairingActivationResult({required this.catalogId, this.fallback = false});

  final String catalogId;
  final bool fallback;
}

/// Enumerates every workspace from disk. Injected from bootstrap so the pairing
/// stack stays ignorant of the session repository.
typedef PairingWorkspaceIndexProvider =
    Future<List<PairingWorkspaceInfo>> Function();

/// Opens/reuses a terminal host-side and returns the resulting catalog id once it
/// is (or is about to become) live. Returns null when nothing could be opened.
/// Injected from bootstrap.
typedef PairingSessionActivator =
    Future<PairingActivationResult?> Function(PairingActivationRequest);

/// Lists directories under [path] host-side (null = the default workspace root),
/// so the phone can pick an existing folder when creating a workspace. Injected
/// from bootstrap.
typedef PairingDirBrowser =
    Future<PairingDirListing> Function(String? path);

/// Creates a workspace host-side over [folderPath], optionally titled and filed
/// under [groupId]. Returns the new workspace id. Injected from bootstrap.
typedef PairingWorkspaceCreator =
    Future<String> Function({
      required String folderPath,
      String? title,
      String? groupId,
    });

/// Creates a workspace group host-side and returns its id. Injected from
/// bootstrap.
typedef PairingGroupCreator = Future<String> Function(String name);

/// Enumerates the desktop's workspace groups so `workspace.list` can advertise
/// them. Injected from bootstrap.
typedef PairingGroupIndexProvider =
    Future<List<PairingGroupInfo>> Function();
