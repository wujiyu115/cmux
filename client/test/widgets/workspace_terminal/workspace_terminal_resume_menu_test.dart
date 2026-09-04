import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/services/cli/sessions/agent_cli_sessions.dart';
import 'package:teampilot/widgets/workspace_terminal/workspace_terminal_resume_menu.dart';

void main() {
  Future<List<TpActionMenuSpec>> buildSpecs(
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
            specs = agentCliResumeMenuSpecs(context, sessions);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    return specs!;
  }

  testWidgets('empty sessions yield one disabled item', (tester) async {
    final specs = await buildSpecs(tester, const []);
    expect(specs, hasLength(1));
    expect(specs.single.isDivider, isFalse);
    expect(specs.single.enabled, isFalse);
    expect(specs.single.value, isNull);
  });

  testWidgets('groups families with headers and dividers', (tester) async {
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
    final specs = await buildSpecs(tester, [claude, codex]);

    expect(specs, hasLength(5));
    // Claude header (disabled, no value), claude item, divider, codex
    // header, codex item.
    expect(specs[0].enabled, isFalse);
    expect(specs[0].value, isNull);
    expect(specs[1].value, claude);
    expect(specs[1].label, 'Claude title');
    expect(specs[1].subtitle, isNotNull);
    expect(specs[2].isDivider, isTrue);
    expect(specs[3].enabled, isFalse);
    expect(specs[3].value, isNull);
    expect(specs[4].value, codex);
    expect(specs[4].label, 'codex-1');
    expect(specs[4].subtitle, isNull);
  });

  testWidgets('long session ids are shortened when untitled', (tester) async {
    final record = const AgentCliSessionRecord(
      family: AgentCliFamily.opencode,
      sessionId: 'ses_3497c111effe0k6mWGLkH7qGx2',
    );
    final specs = await buildSpecs(tester, [record]);
    final label = specs.last.label;
    expect(label, isNotNull);
    expect(label!.startsWith('ses_3497'), isTrue);
    expect(label.endsWith('…'), isTrue);
  });
}
