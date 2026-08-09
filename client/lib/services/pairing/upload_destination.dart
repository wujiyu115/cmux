import '../io/filesystem.dart';

/// First unused path for [filename] in [directory], suffixing `-1`, `-2`, …
/// before the extension. Returns the absolute path to write.
///
/// The loop exists for two load-bearing reasons, and neither is redundant:
///
/// 1. It never overwrites a user's existing file.
/// 2. That same "never overwrite" behaviour is the symlink defence: a
///    pre-existing `photo.jpg` planted in [directory] and pointing at
///    `/etc/passwd` makes us write `photo-1.jpg` instead of following the link
///    and clobbering its target. Anyone changing this must preserve both.
///
/// All path arithmetic goes through the filesystem's own [Filesystem.pathContext]
/// — never a hardcoded separator — because the target may be a remote POSIX host
/// or a WSL distro reached from Windows.
Future<String> resolveUploadDestination({
  required Filesystem filesystem,
  required String directory,
  required String filename,
}) async {
  final pathContext = filesystem.pathContext;
  final extension = pathContext.extension(filename);
  final stem = pathContext.basenameWithoutExtension(filename);
  for (var attempt = 0; attempt < 100; attempt++) {
    final candidate = attempt == 0 ? filename : '$stem-$attempt$extension';
    final path = pathContext.join(directory, candidate);
    final stat = await filesystem.stat(path);
    if (!stat.exists) return path;
  }
  // A directory already holding 100 same-named files is either pathological or
  // an attempt to pin us in this loop.
  throw StateError('no free upload path for $filename in $directory');
}
