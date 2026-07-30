import '../../models/runtime_target.dart';
import '../../repositories/ssh_profile_repository.dart';
import '../host/wsl_distro_lookup.dart';
import 'targets_repository.dart';

/// The list of runtime targets the user can pick a home / workspace target
/// from. `targets.json` persists ssh targets; implicit `local` (and one
/// `wsl:*` per installed distro on Windows) are injected; ssh targets are
/// reconciled against live ssh_profiles.
class RuntimeTargetRegistry {
  RuntimeTargetRegistry({
    required TargetsRepository repo,
    required SshProfileRepository sshProfileRepo,
    required this.isWindows,
    required this.isAndroid,
    Future<List<String>> Function() listWslDistros = WslDistroLookup.list,
  }) : _repo = repo,
       _sshProfileRepo = sshProfileRepo,
       _listWslDistros = listWslDistros;

  final TargetsRepository _repo;
  final SshProfileRepository _sshProfileRepo;
  final Future<List<String>> Function() _listWslDistros;
  final bool isWindows;
  final bool isAndroid;

  /// Merge persisted ssh targets with live ssh_profiles (add new, prune orphans;
  /// write back if changed) plus implicit local / wsl entries.
  Future<List<RuntimeTarget>> listTargets({String wslDistro = ''}) async {
    final file = await _repo.load();
    final profiles = await _sshProfileRepo.loadAll();
    final byId = {for (final p in profiles) p.id: p};

    final reconciled = <RuntimeTarget>[];
    var changed = false;
    for (final t in file.targets) {
      final pid = t.sshProfileId;
      if (pid != null && byId.containsKey(pid)) {
        reconciled.add(t.copyWith(label: byId[pid]!.name));
      } else {
        changed = true; // orphan dropped
      }
    }
    final existingPids = reconciled
        .map((t) => t.sshProfileId)
        .whereType<String>()
        .toSet();
    for (final p in profiles) {
      if (!existingPids.contains(p.id)) {
        reconciled.add(RuntimeTarget.ssh(p.id, label: p.name));
        changed = true;
      }
    }
    if (changed) {
      await _repo.save(file.copyWith(targets: reconciled));
    }

    return [
      RuntimeTarget.local(),
      ...await _wslTargets(wslDistro),
      ...reconciled,
    ];
  }

  /// One `wsl:<distro>` target per installed distro on Windows. The explicit
  /// [wslDistro] (the currently-selected home distro, if any) is merged in so a
  /// selected-but-unlisted distro still appears; order is enumeration order.
  Future<List<RuntimeTarget>> _wslTargets(String wslDistro) async {
    if (!isWindows) return const [];
    final names = <String>[];
    for (final d in await _listWslDistros()) {
      final t = d.trim();
      if (t.isNotEmpty && !names.contains(t)) names.add(t);
    }
    final selected = wslDistro.trim();
    if (selected.isNotEmpty && !names.contains(selected)) {
      names.add(selected);
    }
    return [for (final d in names) RuntimeTarget.wsl(d)];
  }
}
