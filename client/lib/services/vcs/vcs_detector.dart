import 'package:path/path.dart' as p;

import '../io/filesystem.dart';

/// Which version-control system owns a path.
enum VcsKind { git, svn }

/// One contiguous region of a workspace folder governed by one VCS checkout.
///
/// A nested layout (git repo with an svn working copy in `common/`) yields
/// two areas with different roots; each file resolves to the area whose root
/// is the nearest ancestor — mirroring how `.git`/`.svn` discovery works.
class VcsArea {
  const VcsArea({required this.kind, required this.root});

  final VcsKind kind;

  /// Absolute, normalized root of the checkout (the `.git` owner directory,
  /// or the directory containing `.svn`).
  final String root;

  @override
  bool operator ==(Object other) =>
      other is VcsArea && other.kind == kind && other.root == root;

  @override
  int get hashCode => Object.hash(kind, root);

  @override
  String toString() => 'VcsArea($kind, $root)';
}

/// Result of probing one workspace folder.
class VcsProbeResult {
  const VcsProbeResult({required this.areas});

  /// All discovered areas, ordered shallowest root first.
  final List<VcsArea> areas;

  bool get isEmpty => areas.isEmpty;

  /// The area that owns [absolutePath]: the deepest root containing it wins
  /// (nearest `.git`/`.svn` ancestor). In the nested svn-in-git layout, the
  /// svn root is deeper than the git root, so `common/**` resolves to svn
  /// and everything else to git.
  VcsArea? areaForPath(String absolutePath) {
    final ctx = p.context;
    final nPath = ctx.normalize(absolutePath);
    VcsArea? best;
    var bestLen = -1;
    for (final area in areas) {
      final nRoot = ctx.normalize(area.root);
      if (nPath == nRoot || ctx.isWithin(nRoot, nPath)) {
        if (nRoot.length > bestLen) {
          best = area;
          bestLen = nRoot.length;
        }
      }
    }
    return best;
  }
}

/// Probes a workspace folder for git/svn checkouts, including svn working
/// copies nested inside a git repo (e.g. a git project root whose
/// `common/` is a separate svn checkout, gitignored).
///
/// Discovery is directory-based, not command-based: `.git` / `.svn` markers
/// are authoritative, so no `git`/`svn` binary is needed to *detect* — only
/// to *use* an area. All filesystem access goes through [Filesystem], so the
/// same code runs on native/WSL/SSH backends.
class VcsDetector {
  VcsDetector({this.maxSvnScanDepth = 4, this.maxSvnAreas = 8});

  /// How deep below [folder] to walk looking for nested `.svn` directories.
  /// Git needs no downward scan: every path in the folder resolves through
  /// the nearest-root rule anyway.
  final int maxSvnScanDepth;

  /// Cap on nested svn areas discovered in one folder, so pathological
  /// trees (a checkout of dozens of externals) don't explode the panel.
  final int maxSvnAreas;

  Future<VcsProbeResult> probe(String folder, Filesystem fs) async {
    final ctx = fs.pathContext;
    final normalized = ctx.normalize(folder);
    final areas = <VcsArea>[];

    // Upward .git discovery — handles a workspace folder opened at a
    // subdirectory of the repo.
    final gitRoot = await _nearestMarkerRoot(
      normalized,
      '.git',
      fs,
      accept: (s) => s.kind == FsEntityKind.directory || s.kind == FsEntityKind.file,
    );
    if (gitRoot != null) {
      areas.add(VcsArea(kind: VcsKind.git, root: gitRoot));
    }

    // Upward .svn discovery — the folder itself may sit inside an svn wc.
    final svnRoot = await _nearestMarkerRoot(
      normalized,
      '.svn',
      fs,
      accept: (s) => s.kind == FsEntityKind.directory,
    );
    if (svnRoot != null) {
      areas.add(VcsArea(kind: VcsKind.svn, root: svnRoot));
    } else {
      // Nested svn working copies below the folder (svn-in-git). Skipped
      // when the folder is already inside an svn wc: svn doesn't nest wcs
      // except via externals, and those carry their own shallow `.svn`
      // found by this same scan.
      final found = <VcsArea>[];
      final bulk = await fs.findNestedDirsNamed(normalized, '.svn');
      if (bulk != null) {
        // find returns the marker dirs themselves (e.g. `…/common/.svn`);
        // the working-copy root is their parent. Keep only top-level wcs:
        // externals under a found wc (their own shallow `.svn`) surface as
        // rows inside its group, not as separate areas — same fold as the
        // per-directory scan below.
        final roots = [
          for (final marker in bulk)
            if (marker.endsWith('/.svn') || marker.endsWith(r'\.svn'))
              ctx.dirname(marker),
        ]..sort((a, b) => a.length.compareTo(b.length));
        for (final root in roots) {
          if (found.length >= maxSvnAreas) break;
          if (found.any((a) => ctx.isWithin(a.root, root))) continue;
          found.add(VcsArea(kind: VcsKind.svn, root: root));
        }
      } else {
        await _scanNestedSvn(normalized, 0, fs, found);
      }
      areas.addAll(found);
    }

    areas.sort((a, b) => a.root.length.compareTo(b.root.length));
    return VcsProbeResult(areas: areas);
  }

  /// Nearest ancestor of [start] (inclusive) holding [marker]. Null at the
  /// filesystem root. [accept] distinguishes git's worktree-file `.git`
  /// from svn's always-directory `.svn`.
  Future<String?> _nearestMarkerRoot(
    String start,
    String marker,
    Filesystem fs, {
    required bool Function(FsStat) accept,
  }) async {
    final ctx = fs.pathContext;
    var dir = start;
    while (true) {
      final stat = await fs.stat(ctx.join(dir, marker));
      if (stat.kind != FsEntityKind.notFound && accept(stat)) {
        return dir;
      }
      final parent = ctx.dirname(dir);
      if (parent == dir) return null; // filesystem root
      dir = parent;
    }
  }

  /// Depth-limited walk for `.svn` directories below [dir]. Never descends
  /// into hidden directories (`.git`, other `.svn`).
  Future<void> _scanNestedSvn(
    String dir,
    int depth,
    Filesystem fs,
    List<VcsArea> found,
  ) async {
    // depth counts levels already descended: children at depth+1 are only
    // inspected while depth+1 <= maxSvnScanDepth.
    if (depth + 1 > maxSvnScanDepth || found.length >= maxSvnAreas) return;
    final ctx = fs.pathContext;
    final entries = await fs.listDir(dir);
    for (final entry in entries) {
      if (entry.name.startsWith('.')) continue;
      final child = ctx.join(dir, entry.name);
      if (!entry.isDirectory) continue;
      final svnStat = await fs.stat(ctx.join(child, '.svn'));
      if (svnStat.kind == FsEntityKind.directory) {
        found.add(VcsArea(kind: VcsKind.svn, root: child));
        if (found.length >= maxSvnAreas) return;
        // Externals under this wc carry their own `.svn` but surface as
        // rows inside this area's group, not as separate areas.
        continue;
      }
      await _scanNestedSvn(child, depth + 1, fs, found);
    }
  }
}
