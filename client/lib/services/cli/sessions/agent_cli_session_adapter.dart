import 'dart:convert';

import '../../io/filesystem.dart';
import '../../io/sftp_filesystem.dart';
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

  /// Tail read per file: title records are appended as a session evolves, so
  /// the live title sits near EOF — far beyond the head in long sessions.
  static const int tailBytes = 16384;

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
      tailBytes: tailBytes,
    );
    return [
      for (final head in heads)
        AgentCliSessionRecord(
          family: family,
          sessionId: sessionIdOfFileName(head.path),
          title: claudeStyleTitle(head.bytes, tailBytes: head.tailBytes),
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
    final sorted = allFiles.toList()..sort((a, b) => b.compareTo(a));
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
                _sessionIdFromMeta(head.bytes) ??
                sessionIdOfFileName(head.path),
            updatedAt: head.mtime,
          ),
    ];
  }

  /// Newest-first paths, capped to [maxFiles] and the newest [maxDayDirs]
  /// distinct `Y/M/D` prefixes.
  List<String> _newestByDayDirs(
    List<String> sortedRelativePaths,
    int maxFiles,
  ) {
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
        if (_parse(head.bytes) case final json?
            when json['id'] is String &&
                json['directory'] is String &&
                sameCliDirectory(json['directory']! as String, query.directory))
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

/// `~/.omp/agent/sessions/<mungedCwd>/<timestamp>_<sessionId>.jsonl` (oh-my-pi,
/// binary `omp`). The file leads with a `title` record (rewritten in place, so
/// the live title is always on line 1) and a `session` record carrying the
/// session id and cwd.
class OhMyPiAgentCliSessionAdapter implements AgentCliSessionAdapter {
  const OhMyPiAgentCliSessionAdapter();

  @override
  AgentCliFamily get family => AgentCliFamily.ohMyPi;

  /// The title and session records lead the file and the first user prompt
  /// lands within the first few hundred bytes; long turns and tool traffic
  /// come later, so a small head is enough.
  static const int headBytes = 8192;

  @override
  Future<List<AgentCliSessionRecord>> listSessions(
    AgentCliSessionQuery query,
  ) async {
    final io = AgentCliSessionIo(query.context.filesystem);
    final path = query.context.filesystem.pathContext;
    final munged = _sessionDirName(query.directory, query.context.home);
    if (munged == null || munged.isEmpty) return const [];

    final sessionsRoot = path.join(
      query.context.home,
      '.omp',
      'agent',
      'sessions',
    );
    var projectDirName = munged;
    var files = await io.listJsonlFiles(path.join(sessionsRoot, munged));
    if (files.isEmpty) {
      // Windows drive-letter casing, same rationale as the Claude store.
      final siblings = await io.listDir(sessionsRoot);
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
        files = await io.listJsonlFiles(path.join(sessionsRoot, alt.name));
      }
    }
    if (files.isEmpty) return const [];

    final heads = await io.readHeads(
      files.map((name) => path.join(sessionsRoot, projectDirName, name)),
      headBytes: headBytes,
    );
    return [
      for (final head in heads)
        if (ohMyPiSessionRecord(head.bytes, head.path) case final record?)
          record,
    ];
  }

  /// oh-my-pi keys sessions by the munged cwd but strips the home prefix
  /// first, keeping the separator: `/home/u/git/x` is stored under
  /// `-git-x`, while `/tmp/x` stays `-tmp-x`. Verified against the real
  /// `~/.omp/agent/sessions` layout.
  static String? _sessionDirName(String directory, String? home) {
    final trimmed = directory.trim();
    final h = home?.trim();
    if (h != null && h.isNotEmpty) {
      if (trimmed == h) return null;
      if (trimmed.startsWith('$h/')) {
        return mungeDirectory(trimmed.substring(h.length));
      }
    }
    return mungeDirectory(trimmed);
  }
}

/// One resumable record from an oh-my-pi session head: the `session` record's
/// id (falling back to the filename's `<timestamp>_` suffix) plus the title.
AgentCliSessionRecord? ohMyPiSessionRecord(List<int> bytes, String filePath) {
  final lines = _jsonLines(bytes);
  String? sessionId;
  String? title;
  for (final line in lines) {
    switch (line['type']) {
      case 'session':
        final id = line['id'];
        if (id is String && id.isNotEmpty) sessionId ??= id;
      case 'title':
        title ??= shortTitle(line['title']);
      case 'message':
        if (title != null) continue;
        final message = line['message'];
        if (message is Map<String, Object?> && message['role'] == 'user') {
          title ??= shortTitle(_firstUserPrompt(message));
        }
    }
  }
  sessionId ??= _ohMyPiSessionIdFromFileName(filePath);
  if (sessionId == null) return null;
  return AgentCliSessionRecord(
    family: AgentCliFamily.ohMyPi,
    sessionId: sessionId,
    title: title,
  );
}

/// `<timestamp>_<sessionId>.jsonl` → the id part after the first underscore.
String? _ohMyPiSessionIdFromFileName(String filePath) {
  final base = sessionIdOfFileName(filePath);
  final underscore = base.indexOf('_');
  return underscore > 0 ? base.substring(underscore + 1) : null;
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
  Future<Set<String>> listFilesRecursive(
    String root, {
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

  /// Stat + first [headBytes] (and last [tailBytes] when > 0) of the newest
  /// session files among [paths], newest first by mtime.
  ///
  /// Truncation happens only AFTER the mtime sort: directory order is
  /// unrelated to recency, so cutting candidates first would silently drop
  /// the newest sessions. Tail reads are skipped on SFTP, where every read is
  /// a network round trip and the non-batched scan budget barely covers the
  /// head reads.
  Future<List<AgentCliSessionHead>> readHeads(
    Iterable<String> paths, {
    required int headBytes,
    int tailBytes = 0,
  }) async {
    final candidates = paths.toList();
    if (candidates.isEmpty) return const [];
    final tailCap = tailBytes > 0 && fs is! SftpFilesystem ? tailBytes : 0;

    if (!batches) {
      // Local/SFTP stats: stat the newest-looking subset, keep the newest
      // [maxFileReads] of them, then read head + tail of the survivors.
      final stats = <AgentCliSessionHead>[];
      for (final path in candidates.take(maxStatCalls)) {
        try {
          final stat = await fs.stat(path);
          if (stat.isFile) {
            stats.add(
              AgentCliSessionHead(
                path: path,
                mtime: stat.mtime,
                size: stat.size,
              ),
            );
          }
        } on Object {
          // Missing/unreadable file — skip.
        }
      }
      stats.sort(_newestFirst);
      final heads = <AgentCliSessionHead>[];
      for (final stat in stats.take(maxFileReads)) {
        final bytes = await _readHead(stat.path, headBytes);
        final tail = await _readTail(stat, headBytes, tailCap);
        heads.add(stat.copyWith(bytes: bytes, tailBytes: tail));
      }
      return heads;
    }

    // Batched backend: stat + head + tail of every candidate in one round
    // trip (still a single spawn), then keep the newest [maxFileReads]. The
    // candidate list is capped at [maxStatCalls] for spawn argv length.
    final batched = candidates.take(maxStatCalls).toList();
    try {
      final results = await (fs as FsBatchOps).statAndReadBytesMany(
        batched,
        maxBytesPerFile: headBytes,
        tailBytesPerFile: tailCap > 0 ? tailCap : null,
      );
      final heads = [
        for (final path in batched)
          if (results[path] case final head? when head.stat.isFile)
            AgentCliSessionHead(
              path: path,
              mtime: head.stat.mtime,
              size: head.stat.size,
              bytes: head.bytes ?? const [],
              tailBytes: head.tailBytes ?? const [],
            ),
      ]..sort(_newestFirst);
      return heads.take(maxFileReads).toList();
    } on Object {
      // Multi-read unsupported or transport failure — per-file reads below.
    }
    // Degraded fallback: sorting would need a stat per candidate, but each
    // per-file call is its own spawn, so the readdir-order cap stays to bound
    // the latency.
    final heads = <AgentCliSessionHead>[];
    for (final path in batched.take(maxFileReads)) {
      final result = await (fs as FsBatchOps).statAndReadBytes(
        path,
        maxBytes: headBytes,
        tailBytes: tailCap > 0 ? tailCap : null,
      );
      if (result == null || !result.stat.isFile) continue;
      heads.add(
        AgentCliSessionHead(
          path: path,
          mtime: result.stat.mtime,
          size: result.stat.size,
          bytes: result.bytes ?? const [],
          tailBytes: result.tailBytes ?? const [],
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

  /// Last [tailBytes] of a file already covered by a [headBytes] head read;
  /// empty when the whole file fits in the head or the size is unknown.
  Future<List<int>> _readTail(
    AgentCliSessionHead stat,
    int headBytes,
    int tailBytes,
  ) async {
    final size = stat.size;
    if (tailBytes <= 0 || size == null || size <= headBytes) return const [];
    final offset = size > tailBytes ? size - tailBytes : 0;
    try {
      return await fs.readBytesRange(stat.path, offset, tailBytes) ?? const [];
    } on Object {
      return const [];
    }
  }
}

/// Stat + head/tail bytes for one session file.
class AgentCliSessionHead {
  const AgentCliSessionHead({
    required this.path,
    required this.mtime,
    this.size,
    this.bytes = const [],
    this.tailBytes = const [],
  });

  final String path;
  final DateTime? mtime;
  final int? size;
  final List<int> bytes;
  final List<int> tailBytes;

  AgentCliSessionHead copyWith({
    List<int>? bytes,
    List<int>? tailBytes,
  }) => AgentCliSessionHead(
    path: path,
    mtime: mtime,
    size: size,
    bytes: bytes ?? this.bytes,
    tailBytes: tailBytes ?? this.tailBytes,
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

/// Title for Claude-style JSONL, strongest signal first: user rename >
/// generated title > compact summary > first prompt. Title records are
/// appended as a session evolves, so within each kind the LAST record wins —
/// pass the file tail in [tailBytes], where the recent records live.
String? claudeStyleTitle(List<int> bytes, {List<int> tailBytes = const []}) {
  final lines = _jsonLines(bytes).followedBy(_jsonLines(tailBytes));
  String? lastOfType(String type) {
    String? title;
    for (final line in lines) {
      if (line['type'] != type) continue;
      final Object? raw = switch (type) {
        'custom-title' => line['customTitle'],
        'ai-title' => line['aiTitle'],
        _ => line['summary'],
      };
      title = shortTitle(raw) ?? title;
    }
    return title;
  }

  for (final type in const ['custom-title', 'ai-title', 'summary']) {
    if (lastOfType(type) case final title?) return title;
  }
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
  final match = RegExp(
    r'"(?:session_id|id)":"((?:[^"\\]|\\.)*)"',
  ).firstMatch(text);
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
