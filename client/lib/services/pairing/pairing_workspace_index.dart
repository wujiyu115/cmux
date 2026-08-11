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

/// One machine the desktop can bind a workspace folder to — itself, a WSL
/// distro, or an SSH profile — advertised by the extended `workspace.list`.
///
/// This list is load-bearing as a *capability announcement*, not just data: a
/// desktop that predates target selection sends no `targets`, the phone then
/// hides its machine selector and sends no `targetId`, and both sides behave
/// exactly as they did before this field existed. That is why the targets ride
/// on `workspace.list` rather than a separate RPC — asking and being able to ask
/// come from the same field, so there is no version to negotiate.
///
/// [id] is the canonical `local` / `wsl:<distro>` / `ssh:<profileId>` form and
/// stays authoritative; [kind] is the `RuntimeKind` name, for phone-side
/// iconography only. [label] is rendered host-side (`WSL · Ubuntu`, an SSH
/// profile's own name) and must be displayed verbatim — never localized.
class PairingTargetInfo {
  const PairingTargetInfo({
    required this.id,
    required this.label,
    required this.kind,
  });

  final String id;
  final String label;
  final String kind;
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

/// Lists directories under [path] host-side, so the phone can pick an existing
/// folder when creating a workspace. Injected from bootstrap.
///
/// [targetId] names the machine to list on (see [PairingTargetInfo]); null or
/// empty means the host's default plane, byte-identical to the behaviour before
/// this parameter existed. [path], when present, is interpreted **in
/// [targetId]'s namespace** — the pair is coupled, and the protocol can express
/// the nonsense combination of one machine's path with another's id, which the
/// host cannot detect (`/home/me` is plausible on any POSIX target). Keeping
/// them coherent is the caller's job. Null [path] means "start somewhere sane
/// for this target": the default workspace root locally, that machine's home
/// otherwise.
typedef PairingDirBrowser =
    Future<PairingDirListing> Function(String? path, {String? targetId});

/// Creates a workspace host-side over [folderPath], optionally titled and filed
/// under [groupId]. Returns the new workspace id. Injected from bootstrap.
///
/// [targetId] is the machine [folderPath] lives on; null or empty means the
/// host's default plane, as before this parameter existed. It is what makes the
/// workspace's terminal open on that machine — `defaultSessionSpecFor` resolves
/// the runtime target from the folder alone.
typedef PairingWorkspaceCreator =
    Future<String> Function({
      required String folderPath,
      String? title,
      String? groupId,
      String? targetId,
    });

/// Creates a workspace group host-side and returns its id. Injected from
/// bootstrap.
typedef PairingGroupCreator = Future<String> Function(String name);

/// Enumerates the desktop's workspace groups so `workspace.list` can advertise
/// them. Injected from bootstrap.
typedef PairingGroupIndexProvider =
    Future<List<PairingGroupInfo>> Function();

/// Enumerates the machines the desktop can bind a folder to, so `workspace.list`
/// can advertise them. Injected from bootstrap. Must stay cheap — it is served on
/// every `workspace.list`, including the ones pushed on `session.changed`.
typedef PairingTargetIndexProvider =
    Future<List<PairingTargetInfo>> Function();
