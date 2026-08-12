import 'dart:io';
import 'dart:math';

import '../../utils/logging/logger.dart';
import 'agent_attention_state.dart';
import 'agent_status_event.dart';
import 'agent_status_http_handler.dart';
import 'agent_status_headers.dart';

/// App-wide loopback HTTP gateway for seat `POST /agent-status` reports.
///
/// Local seats dial [agentStatusEndpoint] with `X-Session` / `X-Member`
/// headers. Remote (ssh) seats reach the same listener through a reverse
/// tunnel and authenticate with the `X-Bus-Token` value returned by
/// [registerAgentStatusSession].
class AgentStatusGateway {
  AgentStatusGateway();

  final _agentStatusSessions = <String>{};
  final _agentStatusTokenToSession = <String, String>{};
  final _agentStatusSessionToToken = <String, String>{};
  AgentStatusHttpHandler? _agentStatusHandler;
  HttpServer? _http;

  Future<void> ensureStarted() async {
    if (_http != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http = server;
    server.listen(_onRequest);
  }

  /// Closes the HTTP listener (tests / shutdown).
  Future<void> dispose() async {
    for (final sessionId in _agentStatusSessions.toList()) {
      unregisterAgentStatusSession(sessionId);
    }
    await _http?.close(force: true);
    _http = null;
  }

  /// True once [ensureStarted] has bound the loopback listener. Callers that
  /// stamp [agentStatusEndpoint] into a launch env must gate on this: the
  /// gateway is unstarted in tests and whenever agent-status is disabled.
  bool get isStarted => _http != null;

  Uri get agentStatusEndpoint =>
      Uri.parse('http://127.0.0.1:${_http!.port}/agent-status');

  int get httpPort => _http!.port;

  void attachAgentStatusHandler(AgentStatusHttpHandler handler) {
    _agentStatusHandler = handler;
  }

  /// Status session auth.
  ///
  /// Returns the remote [X-Bus-Token] value (provided, existing, or generated).
  /// When [token] is omitted and the session is already registered, reuses the
  /// prior token so multi-seat status-only SSH mounts stay authenticated.
  String registerAgentStatusSession({
    required String sessionId,
    String? token,
  }) {
    _agentStatusSessions.add(sessionId);
    final explicit = token != null && token.isNotEmpty ? token : null;
    if (explicit == null) {
      final existing = _agentStatusSessionToToken[sessionId];
      if (existing != null) return existing;
    }
    final previous = _agentStatusSessionToToken.remove(sessionId);
    if (previous != null) {
      _agentStatusTokenToSession.remove(previous);
    }
    final effective = explicit ?? _randomStatusToken();
    _agentStatusTokenToSession[effective] = sessionId;
    _agentStatusSessionToToken[sessionId] = effective;
    return effective;
  }

  void unregisterAgentStatusSession(String sessionId) {
    _agentStatusSessions.remove(sessionId);
    final token = _agentStatusSessionToToken.remove(sessionId);
    if (token != null) {
      _agentStatusTokenToSession.remove(token);
    }
  }

  Future<void> _onRequest(HttpRequest request) async {
    try {
      // Agent-status is best-effort seat reporting. Never return 4xx here —
      // Claude / flashskyai Stop hooks re-prompt the model on HTTP errors and
      // burn scripted mock turns (or user-visible loops).
      if (request.method == 'POST' && request.uri.path == '/agent-status') {
        await _handleAgentStatus(request, sessionId: _resolveSessionId(request));
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handleAgentStatus(
    HttpRequest request, {
    required String? sessionId,
  }) async {
    final handler = _agentStatusHandler;
    final member = _headerValue(request.headers, agentStatusMemberHeader);
    final allowed =
        sessionId != null &&
        sessionId.isNotEmpty &&
        _agentStatusSessions.contains(sessionId);
    if (handler == null || !allowed || member.isEmpty) {
      // Always 200 (see _onRequest), so a rejection is otherwise invisible.
      final reason = handler == null
          ? 'no handler attached'
          : member.isEmpty
          ? 'empty X-Member header'
          : 'session not registered';
      appLogger.d(
        '[agent-status] rejected: $reason '
        '(session=${sessionId ?? '<none>'} member=${member.isEmpty ? '<none>' : member})',
      );
      await _writeAgentStatusOkEmpty(request);
      return;
    }

    appLogger.d(
      '[agent-status] accepted: session=$sessionId member=$member',
    );
    await handler.handle(request, sessionId: sessionId, memberId: member);
  }

  /// Clears seat attention when a seat reports idle out of band.
  void clearAttentionOnIdle({
    required String sessionId,
    required String memberId,
  }) {
    final handler = _agentStatusHandler;
    if (handler == null) return;
    if (memberId.isEmpty) {
      handler.attention.clearSession(sessionId);
      return;
    }
    // Drop prior sticky PermissionRequest context, then stamp done so idle
    // backup always clears waiting even if a concurrent hook races.
    handler.attention.clearSeat(sessionId: sessionId, memberId: memberId);
    handler.attention.applyEvent(
      sessionId: sessionId,
      memberId: memberId,
      event: const AgentStatusEvent(state: AgentSeatAttention.done),
      skipPermissions: false,
    );
    // If seat-key update missed the waiting row, force a session clear then
    // re-stamp done for this member.
    if (handler.attention.state.sessionHasWaiting(sessionId)) {
      handler.attention.clearSession(sessionId);
      handler.attention.applyEvent(
        sessionId: sessionId,
        memberId: memberId,
        event: const AgentStatusEvent(state: AgentSeatAttention.done),
        skipPermissions: false,
      );
    }
  }

  Future<void> _writeAgentStatusOkEmpty(HttpRequest request) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      )
      ..write('{}');
    await request.response.close();
  }

  String? _resolveSessionId(HttpRequest request) {
    final sessionHeader = _headerValue(
      request.headers,
      agentStatusSessionHeader,
    );
    if (sessionHeader.isNotEmpty) {
      return sessionHeader;
    }

    final token = _headerValue(request.headers, agentStatusTokenHeader);
    if (token.isNotEmpty) {
      return _agentStatusTokenToSession[token];
    }

    return null;
  }
}

/// Case-insensitive header read with forEach fallback (Windows keep-alive).
String _headerValue(HttpHeaders headers, String name) {
  final want = name.toLowerCase();
  final direct = headers.value(want)?.trim() ?? headers.value(name)?.trim();
  if (direct != null && direct.isNotEmpty) return direct;
  var found = '';
  headers.forEach((key, values) {
    if (found.isNotEmpty) return;
    if (key.toLowerCase() == want && values.isNotEmpty) {
      found = values.first.trim();
    }
  });
  return found;
}

String _randomStatusToken() {
  final rng = Random.secure();
  return List.generate(24, (_) => rng.nextInt(16).toRadixString(16)).join();
}
