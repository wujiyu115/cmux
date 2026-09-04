import 'dart:convert';

import '../../io/filesystem.dart';
import '../../storage/runtime_context.dart';
import 'agent_cli_sessions.dart';

/// Inputs for one scan: the target machine's home context and the pane cwd
/// in that machine's native form.
class AgentCliSessionQuery {
  const AgentCliSessionQuery({required this.context, required this.directory});

  final RuntimeContext context;
  final String directory;
}

/// Scans one CLI family's session store for sessions bound to [directory].
abstract interface class AgentCliSessionAdapter {
  AgentCliFamily get family;

  Future<List<AgentCliSessionRecord>> listSessions(AgentCliSessionQuery query);
}

/// `~/{.claude|.qoder}/projects/<mungedCwd>/<sessionId>.jsonl` — one adapter
/// per home dot-dir (both CLIs share the Claude session layout).
class ClaudeStyleAgentCliSessionAdapter implements AgentCliSessionAdapter {
  const ClaudeStyleAgentCliSessionAdapter({
    required this.family,
    required this.homeDotDir,
  });

  @override
  final AgentCliFamily family;

  /// `.claude` or `.qoder` under the target home.
  final String homeDotDir;

  /// Head read per file: Claude-style files can open with several KB of
  /// hook/system metadata before the first user prompt or title line.
  static const int headBytes = 16384;

  @override
  Future<List<AgentCliSessionRecord>> listSessions(
    AgentCliSessionQuery query,
  ) async {
    final io = AgentCliSessionIo(query.context.filesystem);
    final path = query.context.filesystem.pathContext;
    final munged = mungeDirectory(query.directory);
    if (munged.isEmpty) return const [];

    final projectsDir = path.join(query.context.home, homeDotDir, 'projects');
    var projectDirName = munged;
    var files = await io.listJsonlFiles(path.join(projectsDir, munged));
    if (files.isEmpty) {
      // Writers vary in drive-letter casing (`D--git` vs `d--git`).
      final siblings = await io.listDir(projectsDir);
      final alt = siblings
          .where(
            (e) =>
                e.isDirectory &&
                e.name.toLowerCase() == munged.toLowerCase() &&
                e.name != munged,
          )
          .firstOrNull;
      if (alt != null) {
        projectDirName = alt.name;
        files = await io.listJsonlFiles(path.join(projectsDir, alt.name));
      }
    }
    if (files.isEmpty) return const [];

    final heads = await io.readHeads(
      files.map((name) => path.join(projectsDir, projectDirName, name)),
      headBytes: headBytes,
    );
    return [
      for (final head in heads)
        AgentCliSessionRecord(
          family: family,
          sessionId: sessionIdOfFileName(head.path),
          title: claudeStyleTitle(head.bytes),
          updatedAt: head.mtime,
        ),
    ];
  }
}

/// `~/.codex/sessions/<Y>/<M>/<D>/rollout-*.jsonl`; the first line
/// (`session_meta`) carries the session id and cwd within its first bytes.
class CodexAgentCliSessionAdapter implements AgentCliSessionAdapter {
  const CodexAgentCliSessionAdapter();

  @override
  AgentCliFamily get family => AgentCliFamily.codex;

  /// `session_meta` carries the id and cwd before the (multi-KB) system
  /// prompt bloats the line.
  static const int headBytes = 512;
  static const int maxDayDirs = 3;

  @override
  Future<List<AgentCliSessionRecord>> listSessions(
    AgentCliSessionQuery query,
  ) async {
    final io = AgentCliSessionIo(query.context.filesystem);
    final path = query.context.filesystem.pathContext;
    final sessionsRoot = path.join(query.context.home, '.codex', 'sessions');

    final allFiles = await io.listFilesRecursive(
      sessionsRoot,
      extension: '.jsonl',
    );
    // Filenames embed the creation timestamp, so a path sort is a time sort.
    final sorted = allFiles.toList()
      ..sort((a, b) => b.compareTo(a));
    final newest = _newestByDayDirs(sorted, io.maxFileReads);
    if (newest.isEmpty) return const [];

    final heads = await io.readHeads(
      newest.map((rel) => path.joinAll([sessionsRoot, ...rel.split('/')])),
      headBytes: headBytes,
    );
    return [
      for (final head in heads)
        if (_matchesDirectory(head.bytes, query.directory))
          AgentCliSessionRecord(
            family: family,
            sessionId:
                _sessionIdFromMeta(head.bytes) ?? sessionIdOfFileName(head.path),
            updatedAt: head.mtime,
          ),
    ];
  }

  /// Newest-first paths, capped to [maxFiles] and the newest [maxDayDirs]
  /// distinct `Y/M/D` prefixes.
  List<String> _newestByDayDirs(List<String> sortedRelativePaths, int maxFiles) {
    final picked = <String>[];
    final seenDays = <String>{};
    for (final rel in sortedRelativePaths) {
      final parts = rel.split('/');
      if (parts.length < 4) continue;
      final day = parts.sublist(0, 3).join('/');
      if (seenDays.add(day) && seenDays.length > maxDayDirs) break;
      picked.add(rel);
      if (picked.length >= maxFiles) break;
    }
    return picked;
  }
}

/// `~/.local/share/opencode/storage/session/<projectId>/ses_*.json`; each
/// small file carries id, directory, title, and updated time.
class OpencodeAgentCliSessionAdapter implements AgentCliSessionAdapter {
  const OpencodeAgentCliSessionAdapter();

  @override
  AgentCliFamily get family => AgentCliFamily.opencode;

  @override
  Future<List<AgentCliSessionRecord>> listSessions(
    AgentCliSessionQuery query,
  ) async {
    final io = AgentCliSessionIo(query.context.filesystem);
    final path = query.context.filesystem.pathContext;
    final sessionsRoot = path.join(
      query.context.home,
      '.local',
      'share',
      'opencode',
      'storage',
      'session',
    );

    final allFiles = await io.listFilesRecursive(
      sessionsRoot,
      extension: '.json',
    );
    if (allFiles.isEmpty) return const [];

    final heads = await io.readHeads(
      allFiles.map((rel) => path.joinAll([sessionsRoot, ...rel.split('/')])),
      headBytes: 4096,
    );
    return [
      for (final head in heads)
        if (_parse(head.bytes)
            case final json?
            when json['id'] is String &&
                json['directory'] is String &&
                sameCliDirectory(
                  json['directory']! as String,
                  query.directory,
                ))
          AgentCliSessionRecord(
            family: family,
            sessionId: json['id']! as String,
            title: shortTitle(json['title']),
            updatedAt: _updatedFromMs(json['time']),
          ),
    ];
  }

  Map<String, Object?>? _parse(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      return decoded is Map<String, Object?> ? decoded : null;
    } on Object {
      return null;
    }
  }

  DateTime? _updatedFromMs(Object? time) {
    if (time is! Map<String, Object?>) return null;
    final updated = time['updated_ms'] ?? time['updated'];
    if (updated is! int) return null;
    return DateTime.fromMillisecondsSinceEpoch(updated, isUtc: true);
  }
}

// ---------------------------------------------------------------------------
// Shared backend-aware IO
// ---------------------------------------------------------------------------

/// Reads capped file heads through a [Filesystem], keeping per-op backends
/// (WSL: every call is a `wsl.exe` spawn) inside a small round-trip budget.
class AgentCliSessionIo {
  AgentCliSessionIo(this.fs);

  final Filesystem fs;

  bool get batches => fs is FsBatchOps;

  /// Hard cap on stat+head reads per adapter call. Batched backends pay a
  /// process spawn per read (~350ms), so they get a much smaller budget.
  int get maxFileReads => batches ? 6 : 20;

  /// Upper bound on stat calls before the mtime sort. Local stats are cheap
  /// but remote (SFTP) ones are round trips.
  static const int maxStatCalls = 64;

  Future<List<FsDirEntry>> listDir(String path) async {
    try {
      return await fs.listDir(path);
    } on Object {
      return const [];
    }
  }

  /// `*.[extension]` file names directly under [dir].
  Future<List<String>> listJsonlFiles(String dir) async => [
    for (final entry in await listDir(dir))
      if (!entry.isDirectory && entry.name.endsWith('.jsonl')) entry.name,
  ];

  /// Files with [extension] anywhere under [root], as `/`-separated relative
  /// paths. One recursive listing covers the whole store, which keeps
  /// batched backends at a single spawn for discovery.
  Future<Set<String>> listFilesRecursive(String root, {
    required String extension,
  }) async {
    try {
      final entries = await fs.listDirRecursive(root);
      return {
        for (final entry in entries)
          if (!entry.isDirectory && entry.name.endsWith(extension))
            entry.name.replaceAll('\\', '/'),
      };
    } on Object {
      return const {};
    }
  }

  /// Stat + first [headBytes] of up to [maxFileReads] paths, newest first by
  /// mtime when the backend exposes it.
  Future<List<AgentCliSessionHead>> readHeads(
    Iterable<String> paths, {
    required int headBytes,
  }) async {
    final candidates = paths.toList();
    if (candidates.isEmpty) return const [];

    if (!batches) {
      // Local/SFTP stats are cheap: stat the newest-looking subset, keep the
      // newest [maxFileReads] of them.
      final stats = <AgentCliSessionHead>[];
      for (final path in candidates.take(maxStatCalls)) {
        try {
          final stat = await fs.stat(path);
          if (stat.isFile) {
            stats.add(AgentCliSessionHead(path: path, mtime: stat.mtime));
          }
        } on Object {
          // Missing/unreadable file — skip.
        }
      }
      stats.sort(_newestFirst);
      final heads = <AgentCliSessionHead>[];
      for (final stat in stats.take(maxFileReads)) {
        final bytes = await _readHead(stat.path, headBytes);
        heads.add(stat.copyWith(bytes: bytes));
      }
      return heads;
    }

    // Batched backend: the stat and the head arrive in one spawn per file.
    final heads = <AgentCliSessionHead>[];
    for (final path in candidates.take(maxFileReads)) {
      final result = await (fs as FsBatchOps).statAndReadBytes(
        path,
        maxBytes: headBytes,
      );
      if (result == null || !result.stat.isFile) continue;
      heads.add(
        AgentCliSessionHead(
          path: path,
          mtime: result.stat.mtime,
          bytes: result.bytes ?? const [],
        ),
      );
    }
    return heads;
  }

  int _newestFirst(AgentCliSessionHead a, AgentCliSessionHead b) {
    final am = a.mtime;
    final bm = b.mtime;
    if (am != null && bm != null) return bm.compareTo(am);
    if (am != null) return -1;
    if (bm != null) return 1;
    return 0;
  }

  Future<List<int>> _readHead(String path, int headBytes) async {
    try {
      return await fs.readBytesRange(path, 0, headBytes) ?? const [];
    } on Object {
      return const [];
    }
  }
}

/// Stat + head bytes for one session file.
class AgentCliSessionHead {
  const AgentCliSessionHead({
    required this.path,
    required this.mtime,
    this.bytes = const [],
  });

  final String path;
  final DateTime? mtime;
  final List<int> bytes;

  AgentCliSessionHead copyWith({List<int>? bytes}) => AgentCliSessionHead(
    path: path,
    mtime: mtime,
    bytes: bytes ?? this.bytes,
  );
}

// ---------------------------------------------------------------------------
// JSONL parsing helpers
// ---------------------------------------------------------------------------

String sessionIdOfFileName(String filePath) {
  final base = filePath.replaceAll('\\', '/').split('/').last;
  final dot = base.lastIndexOf('.');
  return dot <= 0 ? base : base.substring(0, dot);
}

/// Title for Claude-style JSONL, strongest signal first regardless of line
/// order: user rename > generated title > compact summary > first prompt.
String? claudeStyleTitle(List<int> bytes) {
  final lines = _jsonLines(bytes);
  String? firstMatch(List<String> types) {
    for (final type in types) {
      for (final line in lines) {
        if (line['type'] != type) continue;
        final Object? raw = switch (type) {
          'custom-title' => line['customTitle'],
          'ai-title' => line['aiTitle'],
          _ => line['summary'],
        };
        final title = shortTitle(raw);
        if (title != null) return title;
      }
    }
    return null;
  }

  final titled = firstMatch(const ['custom-title', 'ai-title', 'summary']);
  if (titled != null) return titled;
  for (final line in lines) {
    if (line['type'] == 'user') {
      final title = shortTitle(_firstUserPrompt(line['message']));
      if (title != null) return title;
    }
  }
  return null;
}

String? _firstUserPrompt(Object? message) {
  if (message is! Map<String, Object?>) return null;
  final content = message['content'];
  if (content is String) return content;
  if (content is List) {
    for (final block in content) {
      if (block is Map<String, Object?> && block['type'] == 'text') {
        final text = block['text'];
        if (text is String) return text;
      }
    }
  }
  return null;
}

List<Map<String, Object?>> _jsonLines(List<int> bytes) {
  final text = utf8.decode(bytes, allowMalformed: true);
  return [
    for (final line in const LineSplitter().convert(text))
      if (_tryJsonLine(line) case final json?) json,
  ];
}

Map<String, Object?>? _tryJsonLine(String line) {
  try {
    final decoded = jsonDecode(line);
    return decoded is Map<String, Object?> ? decoded : null;
  } on Object {
    return null;
  }
}

String? shortTitle(Object? raw) {
  if (raw is! String) return null;
  final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) return null;
  return collapsed.length > 80 ? '${collapsed.substring(0, 80)}…' : collapsed;
}

/// Codex `session_meta` first line: the id appears before the embedded system
/// prompt bloats the line, and the head may cut the line mid-way, so match by
/// regex instead of full-line JSON parsing.
String? _sessionIdFromMeta(List<int> bytes) {
  final text = utf8.decode(bytes, allowMalformed: true);
  final match = RegExp(r'"(?:session_id|id)":"((?:[^"\\]|\\.)*)"')
      .firstMatch(text);
  if (match == null) return null;
  return _unescapeJsonString(match.group(1)!);
}

bool _matchesDirectory(List<int> bytes, String directory) {
  final text = utf8.decode(bytes, allowMalformed: true);
  final match = RegExp(r'"cwd":"((?:[^"\\]|\\.)*)"').firstMatch(text);
  if (match == null) return false;
  final cwd = _unescapeJsonString(match.group(1)!);
  return cwd != null && sameCliDirectory(cwd, directory);
}

String? _unescapeJsonString(String escaped) {
  try {
    return jsonDecode('"$escaped"') as String;
  } on Object {
    return null;
  }
}
