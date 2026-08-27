import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/services/agent_status/agent_attention_state.dart';
import 'package:teampilot/services/agent_status/agent_status_event.dart';

AgentAttentionCubit _cubit({DateTime Function()? clock}) {
  final c = AgentAttentionCubit(clock: clock, pruneInterval: null);
  addTearDown(c.close);
  return c;
}

void main() {
  group('AgentAttentionCubit', () {
    test('setSeatState waiting then sessionHasWaiting', () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      expect(
        c.state.attentionFor(sessionId: 's1', memberId: 'm1'),
        AgentSeatAttention.waiting,
      );
      expect(c.state.sessionHasWaiting('s1'), isTrue);
    });

    test('skipPermissions suppresses waiting UI state', () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: true,
      );
      expect(c.state.attentionFor(sessionId: 's1', memberId: 'm1'), isNull);
      expect(c.state.sessionHasWaiting('s1'), isFalse);
    });

    test('skipPermissions keeps prior non-waiting state', () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.working),
        skipPermissions: false,
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: true,
      );
      expect(
        c.state.attentionFor(sessionId: 's1', memberId: 'm1'),
        AgentSeatAttention.working,
      );
      expect(c.state.sessionHasWaiting('s1'), isFalse);
    });

    test('clearSeat removes entry', () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      c.clearSeat(sessionId: 's1', memberId: 'm1');
      expect(c.state.attentionFor(sessionId: 's1', memberId: 'm1'), isNull);
      expect(c.state.sessionHasWaiting('s1'), isFalse);
    });

    test('done clears waiting', () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.done),
        skipPermissions: false,
      );
      expect(
        c.state.attentionFor(sessionId: 's1', memberId: 'm1'),
        AgentSeatAttention.done,
      );
      expect(c.state.sessionHasWaiting('s1'), isFalse);
    });

    test('multi-seat waitingMemberIds', () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm2',
        event: const AgentStatusEvent(state: AgentSeatAttention.working),
        skipPermissions: false,
      );
      expect(c.state.sessionHasWaiting('s1'), isTrue);
      expect(c.state.waitingMemberIds('s1'), ['m1']);
    });

    test('clearSession removes all seats for session', () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm2',
        event: const AgentStatusEvent(state: AgentSeatAttention.working),
        skipPermissions: false,
      );
      c.applyEvent(
        sessionId: 's2',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      c.clearSession('s1');
      expect(c.state.attentionFor(sessionId: 's1', memberId: 'm1'), isNull);
      expect(c.state.attentionFor(sessionId: 's1', memberId: 'm2'), isNull);
      expect(
        c.state.attentionFor(sessionId: 's2', memberId: 'm1'),
        AgentSeatAttention.waiting,
      );
    });

    test('stale entries older than 30m are dropped', () {
      var now = DateTime.utc(2026, 7, 19, 12);
      final c = _cubit(clock: () => now);
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      now = now.add(const Duration(minutes: 31));
      expect(c.state.sessionHasWaiting('s1'), isFalse);
    });

    test('pruneStale emits and removes stale seats from the map', () {
      var now = DateTime.utc(2026, 7, 19, 12);
      final c = _cubit(clock: () => now);
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      final key = agentSeatKey(sessionId: 's1', memberId: 'm1');
      expect(c.state.seats.containsKey(key), isTrue);

      now = now.add(const Duration(minutes: 31));
      // Soft filter alone: map still holds the entry until prune emits.
      expect(c.state.seats.containsKey(key), isTrue);

      c.pruneStale();
      expect(c.state.sessionHasWaiting('s1'), isFalse);
      expect(c.state.seats.containsKey(key), isFalse);
    });

    test('sticky: other-subagent PreToolUse does not clear waiting', () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'PermissionRequest',
          toolName: 'Bash',
          toolInput: 'rm -rf /tmp/x',
          toolAgentId: 'agent-a',
        ),
        skipPermissions: false,
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.working,
          hookEventName: 'PreToolUse',
          toolName: 'Read',
          toolInput: '/tmp/other.txt',
          toolUseId: 'toolu-other',
          toolAgentId: 'agent-b',
        ),
        skipPermissions: false,
      );
      expect(
        c.state.attentionFor(sessionId: 's1', memberId: 'm1'),
        AgentSeatAttention.waiting,
      );
    });

    test('sticky: matching agent_id PreToolUse clears waiting', () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'PermissionRequest',
          toolName: 'Bash',
          toolInput: 'pnpm test',
          toolAgentId: 'agent-a',
          toolAgentType: 'Review',
        ),
        skipPermissions: false,
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.working,
          hookEventName: 'PreToolUse',
          toolName: 'Bash',
          toolInput: 'pnpm test',
          toolUseId: 'toolu-approved',
          toolAgentId: 'agent-a',
          toolAgentType: 'Review',
        ),
        skipPermissions: false,
      );
      expect(
        c.state.attentionFor(sessionId: 's1', memberId: 'm1'),
        AgentSeatAttention.working,
      );
    });

    test('sticky: inherits tool_use_id then PostToolUse clears', () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.working,
          hookEventName: 'PreToolUse',
          toolName: 'Bash',
          toolInput: 'echo hi',
          toolUseId: 'toolu-1',
        ),
        skipPermissions: false,
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'PermissionRequest',
          toolName: 'Bash',
          toolInput: 'echo hi',
        ),
        skipPermissions: false,
      );
      expect(
        c.state.seats[agentSeatKey(sessionId: 's1', memberId: 'm1')]
            ?.lastEvent
            ?.toolUseId,
        'toolu-1',
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.working,
          hookEventName: 'PostToolUse',
          toolName: 'Bash',
          toolInput: 'echo hi',
          toolUseId: 'toolu-1',
        ),
        skipPermissions: false,
      );
      expect(
        c.state.attentionFor(sessionId: 's1', memberId: 'm1'),
        AgentSeatAttention.working,
      );
    });

    test('synthetic working (no hook) clears waiting', () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(
          state: AgentSeatAttention.waiting,
          hookEventName: 'PermissionRequest',
          toolName: 'Bash',
        ),
        skipPermissions: false,
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.working),
        skipPermissions: false,
      );
      expect(
        c.state.attentionFor(sessionId: 's1', memberId: 'm1'),
        AgentSeatAttention.working,
      );
    });

    test('sessionIsAgentActive for waiting and working, not done', () {
      final c = _cubit();
      expect(c.state.sessionIsAgentActive('s1'), isFalse);
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: false,
      );
      expect(c.state.sessionIsAgentActive('s1'), isTrue);
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.working),
        skipPermissions: false,
      );
      expect(c.state.sessionIsAgentActive('s1'), isTrue);
      c.applyEvent(
        sessionId: 's1',
        memberId: 'm1',
        event: const AgentStatusEvent(state: AgentSeatAttention.done),
        skipPermissions: false,
      );
      expect(c.state.sessionIsAgentActive('s1'), isFalse);
    });

    test('sessionIsAgentActive can ignore parked members', () {
      final c = _cubit();
      c.applyEvent(
        sessionId: 's1',
        memberId: 'parked',
        event: const AgentStatusEvent(state: AgentSeatAttention.working),
        skipPermissions: false,
      );
      c.applyEvent(
        sessionId: 's1',
        memberId: 'busy',
        event: const AgentStatusEvent(state: AgentSeatAttention.working),
        skipPermissions: false,
      );
      expect(
        c.state.sessionIsAgentActive(
          's1',
          includeMember: (id) => id != 'parked',
        ),
        isTrue,
      );
      expect(
        c.state.sessionIsAgentActive(
          's1',
          includeMember: (id) => id != 'parked' && id != 'busy',
        ),
        isFalse,
      );
    });

    group('workspaceAgentStatus', () {
      test('empty session set yields none', () {
        final c = _cubit();
        c.applyEvent(
          sessionId: 's1',
          memberId: 'm1',
          event: const AgentStatusEvent(state: AgentSeatAttention.working),
          skipPermissions: false,
        );
        expect(c.state.workspaceAgentStatus(const {}), WorkspaceAgentStatus.none);
      });

      test('single session maps each seat state', () {
        final c = _cubit();
        c.applyEvent(
          sessionId: 's1',
          memberId: 'm1',
          event: const AgentStatusEvent(state: AgentSeatAttention.working),
          skipPermissions: false,
        );
        expect(
          c.state.workspaceAgentStatus({'s1'}),
          WorkspaceAgentStatus.working,
        );
        c.applyEvent(
          sessionId: 's1',
          memberId: 'm1',
          event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
          skipPermissions: false,
        );
        expect(
          c.state.workspaceAgentStatus({'s1'}),
          WorkspaceAgentStatus.waiting,
        );
        c.applyEvent(
          sessionId: 's1',
          memberId: 'm1',
          event: const AgentStatusEvent(state: AgentSeatAttention.done),
          skipPermissions: false,
        );
        expect(c.state.workspaceAgentStatus({'s1'}), WorkspaceAgentStatus.done);
      });

      test('done with interrupted flag reports interrupted', () {
        final c = _cubit();
        c.applyEvent(
          sessionId: 's1',
          memberId: 'm1',
          event: const AgentStatusEvent(
            state: AgentSeatAttention.done,
            interrupted: true,
          ),
          skipPermissions: false,
        );
        expect(
          c.state.workspaceAgentStatus({'s1'}),
          WorkspaceAgentStatus.interrupted,
        );
      });

      test('priority waiting > working > interrupted > done across sessions', () {
        final c = _cubit();
        c.applyEvent(
          sessionId: 's1',
          memberId: 'm1',
          event: const AgentStatusEvent(state: AgentSeatAttention.done),
          skipPermissions: false,
        );
        c.applyEvent(
          sessionId: 's2',
          memberId: 'm1',
          event: const AgentStatusEvent(
            state: AgentSeatAttention.done,
            interrupted: true,
          ),
          skipPermissions: false,
        );
        c.applyEvent(
          sessionId: 's3',
          memberId: 'm1',
          event: const AgentStatusEvent(state: AgentSeatAttention.working),
          skipPermissions: false,
        );
        const ids = {'s1', 's2', 's3'};
        expect(c.state.workspaceAgentStatus(ids), WorkspaceAgentStatus.working);
        c.applyEvent(
          sessionId: 's4',
          memberId: 'm1',
          event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
          skipPermissions: false,
        );
        expect(
          c.state.workspaceAgentStatus({...ids, 's4'}),
          WorkspaceAgentStatus.waiting,
        );
        // Without the interrupted session, done still wins over none but not
        // over working.
        expect(
          c.state.workspaceAgentStatus({'s1', 's3'}),
          WorkspaceAgentStatus.working,
        );
        expect(
          c.state.workspaceAgentStatus({'s1'}),
          WorkspaceAgentStatus.done,
        );
      });

      test('ignores seats from other workspaces sessions', () {
        final c = _cubit();
        c.applyEvent(
          sessionId: 'other',
          memberId: 'm1',
          event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
          skipPermissions: false,
        );
        expect(
          c.state.workspaceAgentStatus({'s1'}),
          WorkspaceAgentStatus.none,
        );
      });

      test('stale seats are ignored', () {
        var now = DateTime.utc(2026, 8, 27, 12);
        final c = _cubit(clock: () => now);
        c.applyEvent(
          sessionId: 's1',
          memberId: 'm1',
          event: const AgentStatusEvent(state: AgentSeatAttention.working),
          skipPermissions: false,
        );
        now = now.add(const Duration(minutes: 31));
        expect(
          c.state.workspaceAgentStatus({'s1'}),
          WorkspaceAgentStatus.none,
        );
      });
    });
  });
}
