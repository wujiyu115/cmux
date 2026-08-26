import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
import 'pairing_upload_target.dart';
import 'upload_destination.dart';

/// How big a batch to hand [Filesystem.appendBytes] for a given backend.
///
/// `WslFilesystem.appendBytes` spawns a `wsl.exe` subprocess running
/// `base64 -d >> path` and pipes the whole base64-encoded payload through its
/// stdin — peak memory around 3.7x the batch, and one process per call.
/// `SftpFilesystem.appendBytes` opens and closes a remote handle per call. Both
/// want large, infrequent bites: at 8 MiB a 512 MiB video costs 64 subprocesses
/// instead of the 8192 a 64 KiB batch would, for ~30 MiB of transient memory.
/// Doubling again to 16 MiB would double that transient to halve an already
/// cheap count.
///
/// `LocalFilesystem.appendBytes` is a bare `RandomAccessFile` open/writeFrom/
/// close, cheap enough to feed in small bites — which keeps resident memory
/// lower and makes progress smoother.
int uploadFlushBytesFor(Filesystem filesystem) =>
    filesystem is LocalFilesystem ? 1 * 1024 * 1024 : 8 * 1024 * 1024;

/// Streams an upload into a hidden part-file next to its destination, then
/// renames it into place on commit.
///
/// Nothing here holds the whole file: [append] goes straight to the filesystem,
/// so host memory is bounded by the receiver's flush batch regardless of how
/// large the upload is or how slow the backend is.
class FilesystemUploadTarget implements PairingUploadTarget {
  FilesystemUploadTarget({
    required this.filesystem,
    required this.directory,
    required this.filename,
    required this.partPath,
    required this.preferredFlushBytes,
  });

  final Filesystem filesystem;

  /// Where the finished file lands — also where [partPath] lives, mandatorily.
  final String directory;

  /// The phone's bare filename. Already validated by the receiver.
  final String filename;

  final String partPath;

  @override
  final int preferredFlushBytes;

  @override
  Future<void> append(List<int> bytes) =>
      filesystem.appendBytes(partPath, bytes);

  /// Resolves a free destination and moves the part-file onto it.
  ///
  /// The destination is resolved here rather than at open so the never-overwrite
  /// check happens as late as possible, preserving the semantics the sink-based
  /// version had.
  ///
  /// The re-stat before each rename is not paranoia. `WslFilesystem.rename` and
  /// `SftpFilesystem.rename` both `removeRecursive(to)` *before* `mv`, so a file
  /// that appeared at the resolved name between resolve and rename would be
  /// deleted. Re-checking narrows that window to one round trip; closing it
  /// entirely needs an atomic-replace primitive no backend offers.
  @override
  Future<String> commit() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final destination = await resolveUploadDestination(
        filesystem: filesystem,
        directory: directory,
        filename: filename,
      );
      if ((await filesystem.stat(destination)).exists) continue;
      await filesystem.rename(partPath, destination);
      return destination;
    }
    throw StateError('upload destination for $filename kept being taken');
  }

  @override
  Future<void> abort() async {
    try {
      await filesystem.removeRecursive(partPath);
    } on Object {
      // Abort runs on paths that are already failing; a throw here would mask
      // the original error and the leftover is a hidden zero-value file.
    }
  }
}

/// Creates the part-file and returns a target writing to it.
///
/// The part-file is created empty rather than lazily so a zero-byte transfer's
/// commit has something to rename — the sink-based version produced an empty
/// file for that case and it must keep doing so.
Future<FilesystemUploadTarget> openFilesystemUploadTarget({
  required Filesystem filesystem,
  required String directory,
  required String filename,
}) async {
  await filesystem.ensureDir(directory);
  // Same directory as the destination, mandatorily: `LocalFilesystem.rename`
  // calls `File.rename`, which throws EXDEV across mount points, and
  // `Filesystem.createTempDir` hands back a system temp dir that is frequently
  // a different mount from the user's home. It looks like the obvious primitive
  // here and it is the wrong one.
  final partPath = filesystem.pathContext.join(
    directory,
    uploadPartName(filename),
  );
  await filesystem.appendBytes(partPath, const <int>[]);
  return FilesystemUploadTarget(
    filesystem: filesystem,
    directory: directory,
    filename: filename,
    partPath: partPath,
    preferredFlushBytes: uploadFlushBytesFor(filesystem),
  );
}

int _partCounter = 0;

/// `.<stem>.<micros>-<counter>.tp-upload` — all four properties are load-bearing:
///
/// - leading `.` hides it from `ls` and from the file tree's default view, so a
///   512 MiB video in flight does not appear in the user's tree;
/// - `<micros>-<counter>` keeps two concurrent uploads of the same name apart
///   (same shape `LocalFilesystem.atomicWrite` uses for its temp names);
/// - the extension is `.tp-upload`, never the real one — a half-written `.mp4`
///   invites thumbnailers and media indexers, an obviously-temporary extension
///   does not;
/// - the greppable suffix makes a leaked part-file attributable. A killed
///   process does leak one; there is no sweeper, because telling a stale
///   part-file from a live upload's would need a lock file, which is more
///   machinery than a hidden file deserves.
String uploadPartName(String filename) {
  final dot = filename.lastIndexOf('.');
  final stem = dot > 0 ? filename.substring(0, dot) : filename;
  final micros = DateTime.now().microsecondsSinceEpoch;
  return '.$stem.$micros-${_partCounter++}.tp-upload';
}

/// Suffix of an in-flight upload's part-file. Callers that surface directory
/// contents to the user (the mirror's changed-file list, for one) filter on this
/// so a two-minute upload does not read as a new file appearing in the repo.
const uploadPartSuffix = '.tp-upload';
