import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../host/host_wsl_argv.dart';
import '../storage/remote_file_store.dart';
import 'filesystem.dart';

typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      Encoding? stdoutEncoding,
      Encoding? stderrEncoding,
    });

class WslFilesystem implements Filesystem, FsBatchOps {
  WslFilesystem({String? distro, ProcessRunner? processRunner})
    : _distro = distro?.trim(),
      _processRunner = processRunner ?? _defaultProcessRunner;

  final String? _distro;
  final ProcessRunner _processRunner;

  /// wsl.exe always emits UTF-8, but `Process.run`'s default stdoutEncoding is
  /// the Windows console codepage (GBK on zh-CN) — Chinese filenames from
  /// `find -printf %f` came back as mojibake. Malformed-tolerant so a stray
  /// invalid byte degrades instead of throwing mid-listing.
  static const Encoding _wslOutputEncoding = Utf8Codec(allowMalformed: true);

  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments, {
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) {
    return Process.run(
      executable,
      arguments,
      stdoutEncoding: stdoutEncoding,
      stderrEncoding: stderrEncoding,
    );
  }

  @override
  p.Context get pathContext => p.Context(style: p.Style.posix);

  List<String> _args(List<String> command) {
    // `--exec` runs the command directly via execvp instead of through the
    // distro's default login shell. Without it `wsl.exe -d <distro> <cmd>`
    // hands the whole line to the user's login shell (e.g. zsh), which both
    // emits rc noise and parses shell metacharacters in our argv — notably the
    // `|` in stat's `%F|%s|%Y` format, which it splits into a pipe and breaks.
    return HostWslArgv.prefixDistro(
      distro: _distro,
      command: ['--exec', ...command],
    );
  }

  Future<ProcessResult> _run(List<String> command) {
    return _processRunner(
      'wsl.exe',
      _args(command),
      stdoutEncoding: _wslOutputEncoding,
      stderrEncoding: _wslOutputEncoding,
    );
  }

  Future<void> _checked(List<String> command) async {
    final result = await _run(command);
    if (result.exitCode != 0) {
      throw StateError(
        'wsl ${command.join(' ')} failed (${result.exitCode}): ${result.stderr}',
      );
    }
  }

  @override
  Future<FsStat> stat(String path) async {
    // Pipe-delimited so file-type names with spaces parse cleanly.
    final result = await _run(['stat', '-c', '%F|%s|%Y', '--', path]);
    if (result.exitCode != 0) return const FsStat(kind: FsEntityKind.notFound);
    return _parseStatLine(result.stdout as String);
  }

  FsStat _parseStatLine(String line) {
    final parts = line.trim().split('|');
    if (parts.length < 3) {
      return const FsStat(kind: FsEntityKind.notFound);
    }
    final kind = switch (parts[0]) {
      'directory' => FsEntityKind.directory,
      'regular file' || 'regular empty file' => FsEntityKind.file,
      'symbolic link' => FsEntityKind.symlink,
      _ => FsEntityKind.notFound,
    };
    if (kind == FsEntityKind.notFound) {
      return const FsStat(kind: FsEntityKind.notFound);
    }
    final size = int.tryParse(parts[1]);
    final mtimeSec = int.tryParse(parts[2]);
    return FsStat(
      kind: kind,
      size: size,
      mtime: mtimeSec != null
          ? DateTime.fromMillisecondsSinceEpoch(mtimeSec * 1000)
          : null,
    );
  }

  @override
  Future<void> ensureDir(String path) => _checked(['mkdir', '-p', '--', path]);

  @override
  Future<void> removeRecursive(String path) =>
      _checked(['rm', '-rf', '--', path]);

  @override
  Future<void> rename(String from, String to) async {
    await ensureDir(pathContext.dirname(to));
    await removeRecursive(to);
    await _checked(['mv', '--', from, to]);
  }

  @override
  Future<String?> readString(String path) async {
    // Decode as UTF-8, not the Windows console codepage. `Process.run`'s
    // default systemEncoding (e.g. GBK) mangles non-ASCII file content — a
    // UTF-8 README shows as 乱码. `readBytes` already transfers raw bytes via
    // base64, so decode those.
    final bytes = await readBytes(path);
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Future<List<int>?> readBytes(String path) async {
    final quoted = RemoteFileStore.shellSingleQuote(path);
    final result = await _run([
      'sh',
      '-lc',
      'base64 -w0 $quoted 2>/dev/null || base64 $quoted',
    ]);
    if (result.exitCode != 0) return null;
    final encoded = (result.stdout as String).replaceAll(RegExp(r'\s+'), '');
    if (encoded.isEmpty) return null;
    try {
      return base64.decode(encoded);
    } on Object {
      return null;
    }
  }

  /// One spawn serves stat and content together — every `wsl.exe` invocation
  /// costs a fixed ~350ms process-spend, so merging them halves the editor's
  /// open latency on WSL. `head -c` bounds the transfer so oversized files are
  /// rejected from stat without piping their full content through the pipe.
  @override
  Future<FsStatAndBytes?> statAndReadBytes(String path, {int? maxBytes}) async {
    final read = maxBytes == null
        ? 'base64 -w0 -- "\$1"'
        : 'head -c "\$3" -- "\$1" | base64 -w0';
    final script = 'stat -c "\$2" -- "\$1" || exit 1\n'
        '[ -r "\$1" ] || exit 2\n'
        '$read';
    final args = <String>['sh', '-c', script, 'sh', path, '%F|%s|%Y'];
    if (maxBytes != null) args.add(maxBytes.toString());
    final result = await _run(args);
    final stdout = result.stdout as String;
    final statLineEnd = stdout.indexOf('\n');
    if (result.exitCode == 1 || statLineEnd < 0) return null;
    final stat = _parseStatLine(stdout.substring(0, statLineEnd));
    if (stat.kind == FsEntityKind.notFound) return null;
    if (result.exitCode == 2) return FsStatAndBytes(stat: stat);
    final encoded = stdout
        .substring(statLineEnd + 1)
        .replaceAll(RegExp(r'\s+'), '');
    if (encoded.isEmpty) return FsStatAndBytes(stat: stat, bytes: const []);
    try {
      return FsStatAndBytes(stat: stat, bytes: base64.decode(encoded));
    } on Object {
      return FsStatAndBytes(stat: stat);
    }
  }

  /// One spawn checks every path: one `y`/`n` character per input, in order.
  @override
  Future<Map<String, bool>> existsMany(List<String> paths) async {
    if (paths.isEmpty) return const {};
    const script =
        'for f in "\$@"; do if [ -e "\$f" ]; then printf y; else printf n; fi; done';
    final result = await _run(['sh', '-c', script, 'sh', ...paths]);
    final flags = result.stdout as String;
    if (result.exitCode != 0 || flags.length != paths.length) {
      throw StateError(
        'wsl existsMany failed (${result.exitCode}): ${result.stderr}',
      );
    }
    return {
      for (var i = 0; i < paths.length; i++) paths[i]: flags[i] == 'y',
    };
  }

  Future<String> _collectStreamText(Stream<List<int>> stream) {
    return stream.transform(const Utf8Decoder()).join();
  }

  Future<void> _pipeBase64ToFile(
    String path,
    String encoded, {
    bool append = false,
  }) async {
    await ensureDir(pathContext.dirname(path));
    final quotedPath = RemoteFileStore.shellSingleQuote(path);
    final op = append ? '>>' : '>';
    final process = await Process.start(
      'wsl.exe',
      _args(['sh', '-lc', 'base64 -d $op $quotedPath']),
    );
    final stderrFuture = _collectStreamText(process.stderr);
    unawaited(process.stdout.drain());
    final payload = utf8.encode(encoded);
    const chunkSize = 64 * 1024;
    for (var offset = 0; offset < payload.length; offset += chunkSize) {
      final end = offset + chunkSize < payload.length
          ? offset + chunkSize
          : payload.length;
      process.stdin.add(payload.sublist(offset, end));
    }
    await process.stdin.close();
    final exitCode = await process.exitCode;
    final stderr = await stderrFuture;
    if (exitCode != 0) {
      throw StateError('wsl write failed ($exitCode): $stderr');
    }
  }

  @override
  Future<void> writeString(String path, String content) async {
    final encoded = base64.encode(utf8.encode(content));
    await _pipeBase64ToFile(path, encoded);
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final encoded = base64.encode(bytes);
    await _pipeBase64ToFile(path, encoded);
  }

  @override
  Future<List<int>?> readBytesRange(
    String path,
    int offset,
    int length,
  ) async {
    final quoted = RemoteFileStore.shellSingleQuote(path);
    final result = await _run([
      'sh',
      '-lc',
      'dd if=$quoted bs=1 skip=$offset count=$length 2>/dev/null | '
          'base64 -w0 || dd if=$quoted bs=1 skip=$offset count=$length 2>/dev/null | base64',
    ]);
    if (result.exitCode != 0) return null;
    final encoded = (result.stdout as String).replaceAll(RegExp(r'\s+'), '');
    if (encoded.isEmpty) return <int>[];
    try {
      return base64.decode(encoded);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> appendBytes(String path, List<int> bytes) async {
    final encoded = base64.encode(bytes);
    await _pipeBase64ToFile(path, encoded, append: true);
  }

  @override
  Future<void> atomicWrite(String path, String content) async {
    final tmp = '$path.tmp.${DateTime.now().microsecondsSinceEpoch}';
    await writeString(tmp, content);
    await rename(tmp, path);
  }

  @override
  Future<List<FsDirEntry>> listDir(String path) async {
    final result = await _run([
      'sh',
      '-lc',
      'find ${RemoteFileStore.shellSingleQuote(path)} -mindepth 1 -maxdepth 1 '
          r'-printf "%f\t%y\n"',
    ]);
    if (result.exitCode != 0) return const [];
    final lines = (result.stdout as String).split('\n');
    return [
      for (final line in lines)
        if (line.trim().isNotEmpty)
          FsDirEntry(
            name: line.split('\t').first,
            isDirectory: line.split('\t').last == 'd',
          ),
    ];
  }

  @override
  Future<bool> createSymlink({
    required String target,
    required String linkPath,
  }) async {
    await ensureDir(pathContext.dirname(linkPath));
    await removeRecursive(linkPath);
    await _checked(['ln', '-sf', '--', target, linkPath]);
    return true;
  }

  @override
  Future<String?> readSymlinkTarget(String linkPath) async {
    try {
      final result = await _run(['readlink', '--', linkPath]);
      if (result.exitCode != 0) return null;
      final target = result.stdout.toString().trim();
      return target.isEmpty ? null : target;
    } on Object {
      return null;
    }
  }

  @override
  Future<String?> resolveSymlink(String path) async {
    try {
      final result = await _run(['readlink', '-f', '--', path]);
      if (result.exitCode != 0) return null;
      final resolved = result.stdout.toString().trim();
      return resolved.isEmpty ? null : resolved;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> copyTree({
    required String source,
    required String destination,
  }) async {
    await ensureDir(pathContext.dirname(destination));
    await removeRecursive(destination);
    await ensureDir(destination);
    await _checked([
      'sh',
      '-lc',
      'cp -R -- ${RemoteFileStore.shellSingleQuote('$source/.')} '
          '${RemoteFileStore.shellSingleQuote(destination)}',
    ]);
  }

  @override
  Future<void> copyFile(String source, String destination) async {
    await ensureDir(pathContext.dirname(destination));
    await _checked(['cp', '--', source, destination]);
  }

  @override
  Future<List<FsDirEntry>> listDirRecursive(String path) async {
    final result = await _run([
      'find',
      path,
      '-mindepth',
      '1',
      '-printf',
      r'%P\t%y\n',
    ]);
    if (result.exitCode != 0) return const [];
    final lines = (result.stdout as String).split('\n');
    return [
      for (final line in lines)
        if (line.trim().isNotEmpty)
          FsDirEntry(
            name: line.split('\t').first,
            isDirectory: line.split('\t').last == 'd',
          ),
    ];
  }

  @override
  Future<String> createTempDir({String? prefix, String? parent}) async {
    // The template must be absolute: a relative one makes mktemp create the
    // directory in wsl.exe's process cwd (the app's launch dir under /mnt/…)
    // and return a *relative* path, which callers then can't resolve.
    final base = parent ?? '/tmp';
    final template = pathContext.join(base, '${prefix ?? 'tmp'}XXXXXX');
    final result = await _run(['mktemp', '-d', '--', template]);
    if (result.exitCode != 0) {
      throw StateError('mktemp failed (${result.exitCode}): ${result.stderr}');
    }
    return (result.stdout as String).trim();
  }

  @override
  Future<void> appendString(String path, String content) async {
    final encoded = base64.encode(utf8.encode(content));
    await _pipeBase64ToFile(path, encoded, append: true);
  }
}
