import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/cli/sessions/agent_cli_sessions.dart';
import 'package:teampilot/widgets/workspace_terminal/workspace_terminal_resume_menu.dart';

void main() {
  Future<List<TpActionMenuSpec>> buildFamilySpecs(
    WidgetTester tester,
    List<AgentCliSessionRecord> sessions,
  ) async {
    List<TpActionMenuSpec>? specs;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) {
            specs = agentCliFamilyMenuSpecs(context, sessions);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    return specs!;
  }

  Future<List<TpActionMenuSpec>> buildSessionSpecs(
    WidgetTester tester,
    AgentCliFamily family,
    List<AgentCliSessionRecord> sessions,
  ) async {
    List<TpActionMenuSpec>? specs;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) {
            specs = agentCliSessionMenuSpecs(context, family, sessions);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    return specs!;
  }

  group('agentCliFamilyMenuSpecs (first level)', () {
    testWidgets('empty sessions yield one disabled item', (tester) async {
      final specs = await buildFamilySpecs(tester, const []);
      expect(specs, hasLength(1));
      expect(specs.single.isDivider, isFalse);
      expect(specs.single.enabled, isFalse);
      expect(specs.single.value, isNull);
    });

    testWidgets('one row per family with sessions, newest time as subtitle', (
      tester,
    ) async {
      final claude = AgentCliSessionRecord(
        family: AgentCliFamily.claude,
        sessionId: 'claude-1',
        title: 'Claude title',
        updatedAt: DateTime.now().subtract(const Duration(minutes: 2)),
      );
      final codex = const AgentCliSessionRecord(
        family: AgentCliFamily.codex,
        sessionId: 'codex-1',
      );
      final specs = await buildFamilySpecs(tester, [claude, codex]);

      expect(specs, hasLength(2));
      expect(specs[0].value, AgentCliFamily.claude);
      expect(specs[0].label, 'Claude Code');
      expect(specs[0].subtitle, isNotNull);
      expect(specs[0].trailing, isNotNull);
      expect(specs[1].value, AgentCliFamily.codex);
      expect(specs[1].label, 'Codex');
      // Codex record has no updatedAt → no subtitle.
      expect(specs[1].subtitle, isNull);
    });

    testWidgets('families without sessions are omitted', (tester) async {
      final record = const AgentCliSessionRecord(
        family: AgentCliFamily.ohMyPi,
        sessionId: 'omp-1',
        title: '会话标题',
      );
      final specs = await buildFamilySpecs(tester, [record]);
      expect(specs, hasLength(1));
      expect(specs.single.value, AgentCliFamily.ohMyPi);
      expect(specs.single.label, 'Oh My Pi');
    });
  });

  group('agentCliSessionMenuSpecs (second level)', () {
    testWidgets('back row first, then the family sessions newest first', (
      tester,
    ) async {
      final claudeOld = const AgentCliSessionRecord(
        family: AgentCliFamily.claude,
        sessionId: 'claude-old',
      );
      final claudeNew = AgentCliSessionRecord(
        family: AgentCliFamily.claude,
        sessionId: 'claude-new',
        title: 'Claude title',
        updatedAt: DateTime.now().subtract(const Duration(minutes: 2)),
      );
      final codex = const AgentCliSessionRecord(
        family: AgentCliFamily.codex,
        sessionId: 'codex-1',
      );
      final specs = await buildSessionSpecs(tester, AgentCliFamily.claude, [
        claudeNew,
        codex,
        claudeOld,
      ]);

      // Back row + the two claude sessions only.
      expect(specs, hasLength(3));
      expect(specs[0].label, 'All agents');
      expect(specs[0].icon, Icons.arrow_back);
      expect(specs[1].value, claudeNew);
      expect(specs[1].label, 'Claude title');
      expect(specs[1].subtitle, isNotNull);
      expect(specs[2].value, claudeOld);
      expect(specs[2].label, 'claude-old');
      expect(specs[2].subtitle, isNull);
    });

    testWidgets('long session ids are shortened when untitled', (tester) async {
      final record = const AgentCliSessionRecord(
        family: AgentCliFamily.opencode,
        sessionId: 'ses_3497c111effe0k6mWGLkH7qGx2',
      );
      final specs = await buildSessionSpecs(tester, AgentCliFamily.opencode, [
        record,
      ]);
      final label = specs.last.label;
      expect(label, isNotNull);
      expect(label!.startsWith('ses_3497'), isTrue);
      expect(label.endsWith('…'), isTrue);
    });
  });
}
