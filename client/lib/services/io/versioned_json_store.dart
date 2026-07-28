import 'dart:convert';

import 'package:path/path.dart' as p;

import 'filesystem.dart';

/// A decoded JSON object.
typedef JsonMap = Map<String, dynamic>;

/// Migrates a payload from [fromVersion] to `fromVersion + 1`. Registered in
/// [VersionedJsonStore.migrations] keyed by `fromVersion`.
typedef JsonMigration = JsonMap Function(JsonMap data);

/// Outcome of a [VersionedJsonStore.read].
enum VersionedReadStatus { missing, ok, recoveredFromBackup, quarantined }

/// Result of [VersionedJsonStore.read]; never thrown, so callers decide what
/// to surface to the user.
class VersionedReadResult<T> {
  const VersionedReadResult({
    required this.status,
    this.data,
    this.quarantinePath,
    this.error,
  });

  final VersionedReadStatus status;

  /// Decoded value; null when [status] is `missing` or `quarantined`.
  final T? data;

  /// Path the corrupt primary was renamed to; set only when `quarantined`.
  final String? quarantinePath;

  /// Last decode/migration failure, for diagnostics.
  final Object? error;
}

/// Reads/writes a JSON document wrapped in a `{"version": int, "data": ...}`
/// envelope, with a rotating `-previous` backup, forward migrations, and
/// quarantine of unrecoverable files instead of silent data loss.
class VersionedJsonStore<T> {
  VersionedJsonStore({
    required Filesystem fs,
    required String path,
    required this.currentVersion,
    required T Function(JsonMap data) decode,
    required JsonMap Function(T value) encode,
    Map<int, JsonMigration> migrations = const {},
    DateTime Function() now = DateTime.now,
  }) : _fs = fs,
       _path = path,
       _decode = decode,
       _encode = encode,
       _migrations = migrations,
       _now = now;

  final Filesystem _fs;
  final String _path;
  final int currentVersion;
  final T Function(JsonMap data) _decode;
  final JsonMap Function(T value) _encode;
  final Map<int, JsonMigration> _migrations;
  final DateTime Function() _now;

  static const _encoder = JsonEncoder.withIndent('  ');

  p.Context get _ctx => _fs.pathContext;

  String get path => _path;

  /// Sibling backup path, e.g. `surfaces.json` → `surfaces-previous.json`.
  String get previousPath {
    final dir = _ctx.dirname(_path);
    final ext = _ctx.extension(_path);
    final stem = _ctx.basenameWithoutExtension(_path);
    return _ctx.join(dir, '$stem-previous$ext');
  }

  /// Reads and decodes the document, recovering from the backup and
  /// quarantining unrecoverable primaries as needed. Never throws.
  Future<VersionedReadResult<T>> read() async {
    final primaryStat = await _fs.stat(_path);
    if (!primaryStat.exists) {
      return const VersionedReadResult(status: VersionedReadStatus.missing);
    }

    try {
      final value = await _loadFrom(_path);
      return VersionedReadResult(status: VersionedReadStatus.ok, data: value);
    } catch (primaryError) {
      final backupStat = await _fs.stat(previousPath);
      if (backupStat.exists) {
        try {
          final value = await _loadFrom(previousPath);
          return VersionedReadResult(
            status: VersionedReadStatus.recoveredFromBackup,
            data: value,
            error: primaryError,
          );
        } catch (_) {
          // Backup also unusable; fall through to quarantine.
        }
      }
      final quarantinePath = await _quarantinePrimary();
      return VersionedReadResult(
        status: VersionedReadStatus.quarantined,
        quarantinePath: quarantinePath,
        error: primaryError,
      );
    }
  }

  /// Writes [value], first copying any existing primary to [previousPath].
  Future<void> write(T value) async {
    final existing = await _fs.stat(_path);
    if (existing.exists && existing.isFile) {
      try {
        final current = await _fs.readString(_path);
        if (current != null) await _fs.atomicWrite(previousPath, current);
      } catch (_) {
        // Backup is best-effort; a failed rotation must not block the write.
      }
    }
    final envelope = <String, dynamic>{
      'version': currentVersion,
      'data': _encode(value),
    };
    await _fs.atomicWrite(_path, '${_encoder.convert(envelope)}\n');
  }

  /// Parses, migrates, and decodes the file at [from]. Throws on any corruption.
  Future<T> _loadFrom(String from) async {
    final raw = await _fs.readString(from);
    if (raw == null) throw const FormatException('unreadable file');
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('envelope is not a map');
    final version = decoded['version'];
    final data = decoded['data'];
    if (version is! int) throw const FormatException('missing int version');
    if (data is! Map) throw const FormatException('missing data map');

    if (version > currentVersion) {
      throw FormatException('version $version newer than $currentVersion');
    }
    var payload = Map<String, dynamic>.from(data);
    for (var v = version; v < currentVersion; v++) {
      final migration = _migrations[v];
      if (migration == null) {
        throw FormatException('no migration from version $v');
      }
      payload = migration(payload);
    }
    return _decode(payload);
  }

  /// Renames the corrupt primary to a timestamped `.corrupt-*` sibling. Never
  /// deletes; the backup file is left untouched.
  Future<String> _quarantinePrimary() async {
    final dir = _ctx.dirname(_path);
    final ext = _ctx.extension(_path);
    final stem = _ctx.basenameWithoutExtension(_path);
    final millis = _now().millisecondsSinceEpoch;
    final target = _ctx.join(dir, '$stem.corrupt-$millis$ext');
    await _fs.rename(_path, target);
    return target;
  }
}
