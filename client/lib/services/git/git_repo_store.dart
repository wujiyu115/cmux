import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../cubits/git_cubit.dart';
import '../../cubits/svn_cubit.dart';
import '../storage/runtime_context.dart';
import '../vcs/svn_service.dart';
import 'git_service.dart';

/// App-level registry of long-lived [GitCubit]s, one per repository root and
/// storage target.
///
/// The source-control panel is rebuilt every time its tool tab is selected
/// (the tab switcher only mounts the active view). If each panel owned its own
/// cubit, every open would re-run `git status` from scratch and flash a spinner.
/// Instead the cubit lives here, outliving the panel: reopening a repo shows the
/// last-known status instantly while a background poll refreshes it in place —
/// the "status cache outlives the view" model orca uses.
///
/// A small LRU bound keeps memory flat across a long session; a workspace's
/// folders are always among the most-recently-used, so they are never evicted
/// while in view.
class GitRepoStore {
  GitRepoStore({
    GitCubit Function(String root, RuntimeContext workContext)? cubitFactory,
    int maxRetained = 8,
  }) : _cubitFactory = cubitFactory ?? _defaultFactory,
       _maxRetained = maxRetained;

  static GitCubit _defaultFactory(String root, RuntimeContext workContext) {
    final service =
        GitService.debugOverrideFactory?.call() ??
        GitService.forContext(workContext);
    return GitCubit(service: service)..setRepoRoot(root);
  }

  final GitCubit Function(String root, RuntimeContext workContext)
  _cubitFactory;
  final int _maxRetained;

  /// Workspace-scoped "blame bar visible" toggles, keyed by workspace id.
  /// `git blame` is expensive, so the bar is opt-in per workspace (tab
  /// context menu) and this set outlives tab switches like the cubits do.
  final blameVisibleWorkspaces = ValueNotifier<Set<String>>(<String>{});

  /// Toggles blame visibility for [workspaceId]; returns the new state.
  bool toggleBlame(String workspaceId) {
    final current = Set<String>.of(blameVisibleWorkspaces.value);
    final next = !current.contains(workspaceId);
    next ? current.add(workspaceId) : current.remove(workspaceId);
    blameVisibleWorkspaces.value = current;
    return next;
  }

  /// Per-repo [SvnCubit] registry, same LRU pattern as the git cubits. One
  /// store serves both VCSes; keys share the git `_cacheKey` namespace.
  final Map<String, SvnCubit> _svnCubits = <String, SvnCubit>{};

  /// Test seam for the svn cubit factory (mirrors [cubitFactory]).
  // ignore: unused_field
  static SvnCubit Function(String root, RuntimeContext workContext)?
  _svnCubitFactoryOverride;

  static SvnCubit _defaultSvnFactory(
    String root,
    RuntimeContext workContext,
  ) {
    final service =
        SvnService.debugOverrideFactory?.call() ??
        SvnService.forContext(workContext);
    return SvnCubit(service: service)..setRepoRoot(root);
  }

  /// Returns the retained svn cubit for [root] on [workContext], creating
  /// (and warming) it on first access.
  SvnCubit svnCubitFor(String root, {required RuntimeContext workContext}) {
    final key = _cacheKey(root, workContext);
    final existing = _svnCubits.remove(key);
    if (existing != null) {
      _svnCubits[key] = existing;
      return existing;
    }
    final cubit = _svnCubitFactoryOverride?.call(
          workContext.filesystem.pathContext.normalize(root),
          workContext,
        ) ??
        _defaultSvnFactory(
          workContext.filesystem.pathContext.normalize(root),
          workContext,
        );
    _svnCubits[key] = cubit;
    _evict();
    return cubit;
  }

  /// Normalized `targetId:root` → cubit. Insertion order is the LRU order.
  final Map<String, GitCubit> _cubits = <String, GitCubit>{};

  static String _cacheKey(String root, RuntimeContext workContext) {
    final normalized = p.Context(style: p.Style.posix).normalize(root);
    return '${workContext.target.id}:$normalized';
  }

  /// Returns the retained cubit for [root] on [workContext], creating (and
  /// warming) it on first access.
  GitCubit cubitFor(String root, {required RuntimeContext workContext}) {
    final key = _cacheKey(root, workContext);
    final existing = _cubits.remove(key);
    if (existing != null) {
      _cubits[key] = existing;
      return existing;
    }
    // Normalize with the target's own path style, not the host platform's.
    // A WSL/SSH root like `/home/ejoy/git/Nexterm` must stay posix; the default
    // `p.Context()` on Windows rewrites it to `\home\ejoy\…`, so `git -C` then
    // fails and the repo reads as "not a Git repository".
    final cubit = _cubitFactory(
      workContext.filesystem.pathContext.normalize(root),
      workContext,
    );
    _cubits[key] = cubit;
    _evict();
    return cubit;
  }

  /// Triggers a coalesced refresh for every [roots] entry on [workContext].
  void refreshAll(
    Iterable<String> roots, {
    required RuntimeContext workContext,
  }) {
    for (final root in roots) {
      if (root.isEmpty) continue;
      cubitFor(root, workContext: workContext).refresh();
    }
  }

  void _evict() {
    while (_cubits.length > _maxRetained) {
      final oldestKey = _cubits.keys.first;
      _cubits.remove(oldestKey)?.close();
    }
    while (_svnCubits.length > _maxRetained) {
      final oldestKey = _svnCubits.keys.first;
      _svnCubits.remove(oldestKey)?.close();
    }
  }

  void dispose() {
    blameVisibleWorkspaces.dispose();
    for (final cubit in _cubits.values) {
      cubit.close();
    }
    _cubits.clear();
    for (final cubit in _svnCubits.values) {
      cubit.close();
    }
    _svnCubits.clear();
  }
}
