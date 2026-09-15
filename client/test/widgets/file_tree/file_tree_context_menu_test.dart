import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/file_tree_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_accent.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_index_dirs.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/widgets/file_tree/file_tree_context_menu.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/test_runtime_context.dart';

/// Records scope-rule persists instead of hitting disk, so the menu tests run
/// in plain fake async.
class _RecordingChatCubit extends ChatCubit {
  _RecordingChatCubit() : super(executableResolver: () => 'flashskyai');

  final savedRules = <WorkspaceIndexDirs>[];

  @override
  Future<void> updateWorkspaceMetadata(
    SessionRepository repo,
    String workspaceId, {
    String? display,
    String? defaultProfileId,
    bool? rootSandboxEnvOptIn,
    String? groupId,
    WorkspaceAccentPreset? accent,
    bool clearAccent = false,
    String? defaultShell,
    bool clearDefaultShell = false,
    WorkspaceIndexDirs? indexDirRules,
  }) async {
    savedRules.add(indexDirRules!);
  }
}

Future<FileTreeCubit> _warmCubit() async {
  final fs = InMemoryFilesystem();
  fs.ensureDir('/repo');
  final cubit = FileTreeCubit(fs: fs);
  await cubit.setRoot('/repo');
  return cubit;
}

/// Pumps a bare app with [chat] and a cubit mounted at /repo, then returns
/// the captured body context to open the menu from.
Future<BuildContext> _pumpHost(WidgetTester tester, ChatCubit chat) async {
  late BuildContext captured;
  final theme = ThemeData(useMaterial3: true);
  await tester.pumpWidget(
    TpTheme(
      data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<SessionRepository>.value(
            value: SessionRepository(),
          ),
        ],
        child: BlocProvider<ChatCubit>.value(
          value: chat,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            theme: theme,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  captured = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return captured;
}

/// Installs a platform-channel clipboard mock — without it every Clipboard
/// call parks forever in fake async. `Clipboard.getData` round-trips the last
/// text written by `Clipboard.setData`.
void _installClipboardMock(WidgetTester tester) {
  String? lastText;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          lastText = (call.arguments as Map?)?['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return lastText == null ? null : <String, Object>{'text': lastText!};
      }
      return null;
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
}

/// Opens the context menu for [targetPath] without awaiting it (the menu
/// future only completes once an item is chosen or the menu is dismissed).
Future<void> _openMenu(
  BuildContext context,
  FileTreeCubit cubit,
  String targetPath, {
  required String targetName,
  required bool isDirectory,
}) {
  return FileTreeContextMenu.show(
    context: context,
    tapDetails: TapDownDetails(globalPosition: const Offset(50, 50)),
    cubit: cubit,
    targetPath: targetPath,
    targetName: targetName,
    isDirectory: isDirectory,
    desktopShellActions: false,
    workspaceId: 'ws1',
    workContext: testRuntimeContext('/repo'),
  );
}

/// Drains the AppToast auto-dismiss timer so the test tree ends clean.
Future<void> _drainToast(WidgetTester tester, {int seconds = 5}) async {
  await tester.pump(Duration(seconds: seconds));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('copy relative path puts the root-relative value on the clipboard', (
    tester,
  ) async {
    _installClipboardMock(tester);
    final chat = _RecordingChatCubit();
    addTearDown(chat.close);
    final cubit = await _warmCubit();
    addTearDown(cubit.close);
    final context = await _pumpHost(tester, chat);

    unawaited(
      _openMenu(
        context,
        cubit,
        '/repo/common/convertor',
        targetName: 'convertor',
        isDirectory: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.fileTreeCopyRelativePath));
    await tester.pump();
    await _drainToast(tester, seconds: 3);

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    expect(data?.text, 'common/convertor');
  });

  testWidgets('copy relative path on a file strips to its relative path', (
    tester,
  ) async {
    _installClipboardMock(tester);
    final chat = _RecordingChatCubit();
    addTearDown(chat.close);
    final cubit = await _warmCubit();
    addTearDown(cubit.close);
    final context = await _pumpHost(tester, chat);

    unawaited(
      _openMenu(
        context,
        cubit,
        '/repo/common/main.dart',
        targetName: 'main.dart',
        isDirectory: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.fileTreeCopyRelativePath));
    await tester.pump();
    await _drainToast(tester, seconds: 3);

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    expect(data?.text, 'common/main.dart');
  });

  testWidgets('copy relative path on the root row falls back to its name', (
    tester,
  ) async {
    _installClipboardMock(tester);
    final chat = _RecordingChatCubit();
    addTearDown(chat.close);
    final cubit = await _warmCubit();
    addTearDown(cubit.close);
    final context = await _pumpHost(tester, chat);

    unawaited(
      _openMenu(
        context,
        cubit,
        '/repo',
        targetName: 'repo',
        isDirectory: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.fileTreeCopyRelativePath));
    await tester.pump();
    await _drainToast(tester, seconds: 3);

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    expect(data?.text, 'repo');
  });

  testWidgets('search scope submenu excludes a directory and persists', (
    tester,
  ) async {
    final chat = _RecordingChatCubit();
    addTearDown(chat.close);
    chat.ingestWorkspaceSessionSnapshot(
      workspaces: [
        Workspace(
          workspaceId: 'ws1',
          folders: const [WorkspaceFolder(path: '/repo')],
          createdAt: 1,
        ),
      ],
      sessions: const [],
    );
    final cubit = await _warmCubit();
    addTearDown(cubit.close);
    final context = await _pumpHost(tester, chat);

    unawaited(
      _openMenu(
        context,
        cubit,
        '/repo/common',
        targetName: 'common',
        isDirectory: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.fileTreeSearchScope));
    await tester.pumpAndSettle();
    expect(find.text(l10n.fileTreeSearchScopeExclude), findsOneWidget);
    expect(find.text(l10n.fileTreeSearchScopeInclude), findsOneWidget);

    await tester.tap(find.text(l10n.fileTreeSearchScopeExclude));
    await tester.pump();
    await _drainToast(tester, seconds: 3);

    expect(chat.savedRules.single.excluded, ['common']);
    expect(chat.savedRules.single.included, isEmpty);
  });

  testWidgets('search scope submenu adds a carve-back include rule', (
    tester,
  ) async {
    final chat = _RecordingChatCubit();
    addTearDown(chat.close);
    chat.ingestWorkspaceSessionSnapshot(
      workspaces: [
        Workspace(
          workspaceId: 'ws1',
          folders: const [WorkspaceFolder(path: '/repo')],
          createdAt: 1,
          indexDirRules: WorkspaceIndexDirs(excluded: ['common']),
        ),
      ],
      sessions: const [],
    );
    final cubit = await _warmCubit();
    addTearDown(cubit.close);
    final context = await _pumpHost(tester, chat);

    unawaited(
      _openMenu(
        context,
        cubit,
        '/repo/common/convertor',
        targetName: 'convertor',
        isDirectory: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.fileTreeSearchScope));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.fileTreeSearchScopeInclude));
    await tester.pump();
    await _drainToast(tester, seconds: 3);

    expect(chat.savedRules.single.excluded, ['common']);
    expect(chat.savedRules.single.included, ['common/convertor']);
  });

  testWidgets('an already-configured rule is rejected with a warning', (
    tester,
  ) async {
    final chat = _RecordingChatCubit();
    addTearDown(chat.close);
    chat.ingestWorkspaceSessionSnapshot(
      workspaces: [
        Workspace(
          workspaceId: 'ws1',
          folders: const [WorkspaceFolder(path: '/repo')],
          createdAt: 1,
          indexDirRules: WorkspaceIndexDirs(excluded: ['common']),
        ),
      ],
      sessions: const [],
    );
    final cubit = await _warmCubit();
    addTearDown(cubit.close);
    final context = await _pumpHost(tester, chat);

    unawaited(
      _openMenu(
        context,
        cubit,
        '/repo/common',
        targetName: 'common',
        isDirectory: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.fileTreeSearchScope));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.fileTreeSearchScopeExclude));
    await tester.pump();
    expect(find.text(l10n.workspaceQuickOpenScopeDuplicate), findsOneWidget);
    await _drainToast(tester);

    expect(chat.savedRules, isEmpty);
  });

  testWidgets('the workspace root itself can not become a rule', (tester) async {
    final chat = _RecordingChatCubit();
    addTearDown(chat.close);
    chat.ingestWorkspaceSessionSnapshot(
      workspaces: [
        Workspace(
          workspaceId: 'ws1',
          folders: const [WorkspaceFolder(path: '/repo')],
          createdAt: 1,
        ),
      ],
      sessions: const [],
    );
    final cubit = await _warmCubit();
    addTearDown(cubit.close);
    final context = await _pumpHost(tester, chat);

    unawaited(
      _openMenu(
        context,
        cubit,
        '/repo',
        targetName: 'repo',
        isDirectory: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.fileTreeSearchScope));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.fileTreeSearchScopeExclude));
    await tester.pump();
    expect(find.text(l10n.fileTreeSearchScopeRootNotAllowed), findsOneWidget);
    await _drainToast(tester);

    expect(chat.savedRules, isEmpty);
  });

  testWidgets('files do not get the search scope submenu', (tester) async {
    final chat = _RecordingChatCubit();
    addTearDown(chat.close);
    final cubit = await _warmCubit();
    addTearDown(cubit.close);
    final context = await _pumpHost(tester, chat);

    unawaited(
      _openMenu(
        context,
        cubit,
        '/repo/main.dart',
        targetName: 'main.dart',
        isDirectory: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.fileTreeSearchScope), findsNothing);
    expect(find.text(l10n.fileTreeCopyRelativePath), findsOneWidget);
  });
}
