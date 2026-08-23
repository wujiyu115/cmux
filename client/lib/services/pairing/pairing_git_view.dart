/// Wire shapes for the paired phone's read-only "what changed" view
/// (`git.changes`, `git.diff`).
///
/// Two decisions are load-bearing and should not be "simplified" back:
///
/// - **Staged and unstaged are merged into one list keyed by path.** The phone's
///   question is "what did the agent change in this repo", not "what is in the
///   index" — and a file that is partly staged appears in *both* of git's areas,
///   which would show up twice. So the host folds them and the diff is always
///   working tree vs HEAD ([GitService.diffAgainstHead]), never `--cached`.
/// - **The phone identifies a diff by path alone.** It cannot name a directory
///   to browse or a file outside the repo: the host only accepts a path it has
///   just itself advertised in [PairingGitChanges.files]. That check is the whole
///   authorization story for this feature, and it lives in the RPC handler.
library;

/// One changed path in the mirrored pane's repository. [path] is relative to the
/// repository root; [badge] is git's single-letter code (`M`/`A`/`D`/`R`/`U`/`?`)
/// rendered verbatim by the phone, so a new [GitChangeKind] needs no phone
/// change. [untracked] rides along because the host needs it to pick the right
/// `git diff` form and re-deriving it from [badge] would encode the mapping
/// twice.
class PairingGitFile {
  const PairingGitFile({
    required this.path,
    required this.badge,
    this.untracked = false,
  });

  final String path;
  final String badge;
  final bool untracked;

  Map<String, Object?> toJson() => {
    'path': path,
    'badge': badge,
    if (untracked) 'untracked': true,
  };

  static PairingGitFile? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    if (path is! String || path.isEmpty) return null;
    final badge = raw['badge'];
    return PairingGitFile(
      path: path,
      badge: badge is String && badge.isNotEmpty ? badge : 'M',
      untracked: raw['untracked'] == true,
    );
  }
}

/// Result of `git.changes`: the mirrored pane's repository state.
///
/// [isRepository] false means the pane's cwd is not inside a work tree — a
/// normal, non-error outcome the phone renders as "not a repo" rather than as a
/// failed request.
class PairingGitChanges {
  const PairingGitChanges({
    required this.isRepository,
    this.branch = '',
    this.files = const [],
  });

  static const PairingGitChanges notARepository = PairingGitChanges(
    isRepository: false,
  );

  final bool isRepository;

  /// Current branch, or empty on a detached HEAD.
  final String branch;

  final List<PairingGitFile> files;

  Map<String, Object?> toJson() => {
    'isRepository': isRepository,
    'branch': branch,
    'files': [for (final f in files) f.toJson()],
  };

  static PairingGitChanges fromJson(Map<String, Object?> raw) {
    final rawFiles = raw['files'];
    return PairingGitChanges(
      isRepository: raw['isRepository'] == true,
      branch: raw['branch'] is String ? raw['branch'] as String : '',
      files: [
        if (rawFiles is List)
          for (final entry in rawFiles)
            if (PairingGitFile.fromJson(entry) case final file?) file,
      ],
    );
  }
}

/// Reads the changed-file list for the repository containing [cwd] on the
/// machine that owns the mirrored pane. Injected from bootstrap so the pairing
/// stack stays ignorant of `GitService` and the runtime-context registry.
///
/// [workspaceId] is what makes the machine resolvable: [cwd] alone is ambiguous
/// (`/home/me/app` is plausible on the host, in a distro, and on an SSH target),
/// so the folder-to-target mapping has to come from the workspace — exactly as
/// for the image-upload sink.
typedef PairingGitChangesProvider =
    Future<PairingGitChanges> Function({
      required String workspaceId,
      required String cwd,
    });

/// Unified diff of [path] (working tree vs HEAD) in the repository containing
/// [cwd]. [untracked] selects the `--no-index` form for a file git has never
/// seen. Injected from bootstrap; see [PairingGitChangesProvider].
///
/// The caller has already checked [path] against a list this host produced —
/// this provider does not re-validate it.
typedef PairingGitDiffProvider =
    Future<String> Function({
      required String workspaceId,
      required String cwd,
      required String path,
      required bool untracked,
    });
