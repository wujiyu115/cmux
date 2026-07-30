import '../../models/runtime_target.dart';
import '../io/filesystem.dart';
import 'runtime_context.dart';

/// Bridges the directory-picker UI to runtime-target resolution, so dialogs
/// don't have to wire up the context registry / target catalog themselves.
///
/// Constructed at bootstrap from `RuntimeContextRegistry.forTarget` and
/// `RuntimeTargetRegistry.listTargets`, then provided to the widget tree.
class WorkspaceDirectoryPicker {
  WorkspaceDirectoryPicker({
    required Future<RuntimeContext> Function(RuntimeTarget) resolveContext,
    required Future<List<RuntimeTarget>> Function() listTargets,
  }) : _resolveContext = resolveContext,
       _listTargets = listTargets;

  final Future<RuntimeContext> Function(RuntimeTarget) _resolveContext;
  final Future<List<RuntimeTarget>> Function() _listTargets;

  /// Whether [targetId] resolves to a non-local machine (SSH or WSL) — the
  /// kinds that need the filesystem-backed remote browser instead of the
  /// native picker.
  bool isRemote(String targetId) =>
      runtimeKindOfId(targetId) != RuntimeKind.local;

  /// The target matching [id] from the live catalog, falling back to local.
  Future<RuntimeTarget> targetById(String id) async {
    final targets = await _listTargets();
    for (final t in targets) {
      if (t.id == id) return t;
    }
    return RuntimeTarget.local();
  }

  /// The filesystem for [targetId] (triggers a real SSH connect for ssh
  /// targets — acceptable when the user explicitly opens the remote browser).
  Future<Filesystem> filesystemFor(String targetId) async {
    final ctx = await _resolveContext(await targetById(targetId));
    return ctx.fs;
  }

  /// The home directory for [targetId] — the sensible place to open the browser
  /// at. For WSL this is the distro's `$HOME` (not the Windows cwd that `.`
  /// resolves to); for SSH it is the remote home. Resolution is cached by the
  /// context registry, so this is cheap after [filesystemFor].
  Future<String?> homeFor(String targetId) async {
    final ctx = await _resolveContext(await targetById(targetId));
    final home = ctx.home.trim();
    return home.isEmpty ? null : home;
  }
}
