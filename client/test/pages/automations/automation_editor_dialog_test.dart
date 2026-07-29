import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/chat/model/chat_state.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/automations/automation_editor_dialog.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../support/automation_test_fixtures.dart';
import '../../support/desktop_app_harness.dart';
import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

const _testPresetId = 'preset-test';

ChatCubit _chatCubitWithWorkspace() {
  final cubit = testChatCubit(executableResolver: () => 'claude');
  cubit.applyState(
    ChatState(
      workspaces: [
        Workspace(
          workspaceId: 'ws1',
          folders: [WorkspaceFolder(path: '/repo')],
          createdAt: 1,
        ),
      ],
    ),
  );
  return cubit;
}

CliPresetsCubit _cliPresetsCubitWithPreset() {
  final cubit = CliPresetsCubit(
    repository: CliPresetsRepository(
      fs: InMemoryFilesystem(),
      presetsPath: '/cli-presets.json',
    ),
  );
  cubit.emit(
    CliPresetsState(
      status: CliPresetsLoadStatus.ready,
      presets: [
        CliPreset(
          id: _testPresetId,
          name: 'Default',
          cli: CliTool.claude,
          provider: 'anthropic',
          model: 'claude-sonnet',
          createdAt: 1,
          updatedAt: 1,
        ),
      ],
    ),
  );
  return cubit;
}

Widget _host({
  required AutomationCubit cubit,
  required Widget child,
  CliPresetsCubit? cliPresetsCubit,
  ChatCubit? chatCubit,
  SessionPreferencesCubit? sessionPreferencesCubit,
}) {
  final resolvedChat = chatCubit ?? _chatCubitWithWorkspace();
  final providers = <BlocProvider>[
    BlocProvider<AutomationCubit>.value(value: cubit),
    BlocProvider<ChatCubit>.value(value: resolvedChat),
  ];
  if (sessionPreferencesCubit != null) {
    providers.add(
      BlocProvider<SessionPreferencesCubit>.value(
        value: sessionPreferencesCubit,
      ),
    );
  }
  if (cliPresetsCubit != null) {
    providers.add(BlocProvider<CliPresetsCubit>.value(value: cliPresetsCubit));
  }

  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: MultiBlocProvider(
        providers: providers,
        child: CliToolRegistryScope(
          registry: CliToolRegistry.builtIn(),
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('scheduled message editor shows core fields only', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    addTearDown(setup.cubit.close);

    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        child: AutomationEditorDialog(
          kind: AutomationEditorKind.scheduledMessage,
          workspaceId: 'ws1',
          sessionId: 'sess-1',
          defaultName: 'Daily ping',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(AutomationEditorDialog)),
    );

    expect(find.text(l10n.automationsCompactTitle), findsOneWidget);
    expect(find.text(l10n.automationsName), findsOneWidget);
    expect(find.text(l10n.automationsMessage), findsOneWidget);
    expect(find.text(l10n.automationsEnabled), findsOneWidget);
    expect(find.text(l10n.presetPickerTitle), findsNothing);
    expect(find.text(l10n.automationsTargetMember), findsNothing);
    expect(find.text(l10n.automationsLaunchMode), findsNothing);
  });

  testWidgets('simple launch prompt shows landing-aligned fields', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    final chatCubit = _chatCubitWithWorkspace();
    final cliPresetsCubit = _cliPresetsCubitWithPreset();
    final sessionPreferencesCubit =
        (await tester.runAsync(testSessionPreferencesCubit))!;
    addTearDown(setup.cubit.close);
    addTearDown(chatCubit.close);
    addTearDown(cliPresetsCubit.close);
    addTearDown(sessionPreferencesCubit.close);

    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        chatCubit: chatCubit,
        cliPresetsCubit: cliPresetsCubit,
        sessionPreferencesCubit: sessionPreferencesCubit,
        child: const AutomationEditorDialog(workspaceId: 'ws1'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(AutomationEditorDialog)),
    );

    expect(find.text(l10n.automationsCreateTitle), findsOneWidget);
    expect(find.text(l10n.presetPickerTitle), findsOneWidget);
    expect(find.text(l10n.automationsPermissions), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text(l10n.automationsTargetMember), findsNothing);
  });


  testWidgets('scheduled message editor pre-fills session defaults', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    addTearDown(setup.cubit.close);

    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        child: AutomationEditorDialog(
          kind: AutomationEditorKind.scheduledMessage,
          workspaceId: 'ws1',
          sessionId: 'sess-1',
          defaultName: 'Daily ping',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final nameField = tester.widget<TextField>(find.byType(TextField).first);
    expect(nameField.controller?.text, 'Daily ping');
  });

  testWidgets('empty message save shows TpForm field validation', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    addTearDown(setup.cubit.close);

    await tester.pumpWidget(
      _host(
        cubit: setup.cubit,
        child: AutomationEditorDialog(
          kind: AutomationEditorKind.scheduledMessage,
          workspaceId: 'ws1',
          sessionId: 'sess-1',
          defaultName: 'Daily ping',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(AutomationEditorDialog)),
    );

    expect(find.byType(TpForm), findsOneWidget);

    await tester.tap(find.text(l10n.save));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(l10n.automationsValidationRequired), findsWidgets);
    expect(setup.cubit.state.automations, isEmpty);
  });
}
