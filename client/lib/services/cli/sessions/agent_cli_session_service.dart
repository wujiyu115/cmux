import '../../../models/runtime_target.dart';
import '../../storage/runtime_context.dart';
import 'agent_cli_session_adapter.dart';
import 'agent_cli_sessions.dart';

/// Scans the installed agent CLIs' session stores on a runtime target for
/// sessions bound to one directory, and hands out their resume commands.
class AgentCliSessionService {
  AgentCliSessionService({
    required Future<RuntimeContext> Function(RuntimeTarget target)
    resolveContext,
    List<AgentCliSessionAdapter>? adapters,
    Duration timeout = const Duration(seconds: 3),
  }) : _resolveContext = resolveContext,
       _adapters = adapters ?? defaultAgentCliSessionAdapters(),
       _timeout = timeout;

  final Future<RuntimeContext> Function(RuntimeTarget target) _resolveContext;
  final List<AgentCliSessionAdapter> _adapters;
  final Duration _timeout;

  static List<AgentCliSessionAdapter> defaultAgentCliSessionAdapters() => [
    const ClaudeStyleAgentCliSessionAdapter(
      family: AgentCliFamily.claude,
      homeDotDir: '.claude',
    ),
    const ClaudeStyleAgentCliSessionAdapter(
      family: AgentCliFamily.qoder,
      homeDotDir: '.qoder',
    ),
    const CodexAgentCliSessionAdapter(),
    const OpencodeAgentCliSessionAdapter(),
  ];

  /// Sessions across all families for [directory], newest first. Adapters run
  /// in parallel; a failing or slow adapter contributes nothing rather than
  /// failing the scan.
  Future<List<AgentCliSessionRecord>> listSessions({
    required RuntimeTarget target,
    required String directory,
  }) async {
    final dir = directory.trim();
    if (dir.isEmpty) return const [];
    final RuntimeContext context;
    try {
      context = await _resolveContext(target);
    } on Object {
      return const [];
    }

    final query = AgentCliSessionQuery(context: context, directory: dir);
    final results = await Future.wait(
      _adapters.map((adapter) => _safeList(adapter, query)),
    );
    final records = [for (final result in results) ...result];
    records.sort(_newestFirst);
    return records;
  }

  /// Shell command that resumes [record] in a pane.
  String resumeCommandFor(AgentCliSessionRecord record) =>
      record.family.resumeCommand(record.sessionId);

  Future<List<AgentCliSessionRecord>> _safeList(
    AgentCliSessionAdapter adapter,
    AgentCliSessionQuery query,
  ) async {
    try {
      return await adapter.listSessions(query).timeout(
        _timeout,
        onTimeout: () => const [],
      );
    } on Object {
      return const [];
    }
  }

  int _newestFirst(AgentCliSessionRecord a, AgentCliSessionRecord b) {
    final at = a.updatedAt;
    final bt = b.updatedAt;
    if (at != null && bt != null) return bt.compareTo(at);
    if (at != null) return -1;
    if (bt != null) return 1;
    return 0;
  }
}
