import 'dart:async';

import '../../models/runtime_target.dart';
import '../io/filesystem.dart';
import '../storage/remote_directory_browser.dart';
import 'pairing_workspace_index.dart';

/// Resolves one machine's filesystem for a phone-supplied target id. An empty id
/// means the host's default plane.
typedef PairingTargetFilesystem = Future<Filesystem> Function(String targetId);

/// That machine's home directory, or null when it has none to offer.
typedef PairingTargetHome = Future<String?> Function(String targetId);

/// Validates a phone-supplied target id and returns the id to act on (empty for
/// "default plane"). Throws when the id names a machine the host does not have.
typedef PairingTargetResolver = Future<String> Function(String? rawTargetId);

/// Serves `fs.browse` for the pairing host: picks the right machine, picks a
/// sensible starting directory for it, and lists.
///
/// Split out of the bootstrap closure it used to live in because two of its
/// decisions fail *silently* and would otherwise have no test:
///
/// - A remote target must not start at `resolveInitial('.')`. For WSL, `.` is the
///   Windows working directory translated to `/mnt/c/...`, so the phone would
///   open the browser inside a mount of the drive it was trying to get away from
///   (the desktop's own dialog documents this at
///   `remote_directory_browser_dialog.dart:66-69`). Remote targets start at that
///   machine's home instead.
/// - An unknown target id must be rejected rather than resolved. The picker
///   behind [PairingTargetFilesystem] falls back to the local machine for ids it
///   does not know, which would list Windows while the phone believes it is
///   looking at a distro.
class PairingHostDirBrowser {
  PairingHostDirBrowser({
    required PairingTargetResolver resolveTargetId,
    required PairingTargetFilesystem filesystemFor,
    required PairingTargetHome homeFor,
    required Future<String> Function() defaultLocalRoot,
    Duration resolveTimeout = const Duration(seconds: 25),
  })  : _resolveTargetId = resolveTargetId,
        _filesystemFor = filesystemFor,
        _homeFor = homeFor,
        _defaultLocalRoot = defaultLocalRoot,
        _resolveTimeout = resolveTimeout;

  final PairingTargetResolver _resolveTargetId;
  final PairingTargetFilesystem _filesystemFor;
  final PairingTargetHome _homeFor;
  final Future<String> Function() _defaultLocalRoot;

  /// Ceiling on resolving a machine's filesystem. A cold SSH target does three
  /// serial network round trips (connect, remote `$HOME`, SFTP open), any of
  /// which can hang on a blackholed host. Bounding it here — below the phone's
  /// own `fs.browse` budget — means the phone gets a real error frame naming the
  /// timeout instead of falling back to its generic one.
  final Duration _resolveTimeout;

  /// An empty id is the host's default plane, which is local by construction.
  static bool _isRemote(String targetId) =>
      targetId.isNotEmpty && runtimeKindOfId(targetId) != RuntimeKind.local;

  Future<PairingDirListing> browse(String? path, {String? targetId}) async {
    final id = await _resolveTargetId(targetId);
    final fs = await _filesystemFor(id).timeout(_resolveTimeout);
    final browser = RemoteDirectoryBrowser(fs);

    final requested = (path ?? '').trim();
    final String start;
    if (requested.isNotEmpty) {
      start = await browser.resolveInitial(requested);
    } else if (!_isRemote(id)) {
      start = await _defaultLocalRoot();
    } else {
      // Deliberately not resolveInitial(null) — see the class doc.
      final home = await _homeFor(id).timeout(_resolveTimeout);
      start = await browser.resolveInitial(
        home == null || home.trim().isEmpty ? '/' : home,
      );
    }

    final listing = await browser.list(start);
    return PairingDirListing(
      path: listing.path,
      parent: listing.parent,
      dirs: listing.directories,
    );
  }
}
