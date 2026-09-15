import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_accent.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_index_dirs.dart';
import 'package:teampilot/pages/home_workspace/workspace_quick_open_scope_dialog.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

/// Stands in for the plugin's platform channel: [savePath]/[pickPath] are the
/// "user's" dialog answers and [lastSaveFileName] records the offered name.
class _FakeFilePicker extends FilePicker {
  String? savePath;
  String? pickPath;
  String? lastSaveFileName;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    lastSaveFileName = fileName;
    return savePath;
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    final path = pickPath;
    if (path == null) return null;
    return FilePickerResult([
      PlatformFile(name: 'search-scope.json', path: path, size: 0),
    ]);
  }
}

/// Records scope-dialog persists instead of hitting disk, so the dialog
/// behavior tests run in plain fake async. [failNextWith] makes the next
/// persist throw once, exercising the dialog's rollback path.
class _RecordingChatCubit extends ChatCubit {
  _RecordingChatCubit() : super(executableResolver: () => 'flashskyai');

  final savedRules = <WorkspaceIndexDirs>[];
  Object? failNextWith;

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
    final failure = failNextWith;
    if (failure != null) {
      failNextWith = null;
      throw failure;
    }
    savedRules.add(indexDirRules!);
  }
}

/// Pumps a bare app with a recording cubit, opens the scope dialog over
/// [initial] rules, and returns the cubit for persist assertions.
///
/// Icon finders line up with section order (exclude = 0, include = 1); the
/// dialog header's own close button is [Icons.close_rounded] index 0, so row
/// remove buttons start at index 1.
Future<_RecordingChatCubit> _pumpDialog(
  WidgetTester tester, {
  WorkspaceIndexDirs initial = const WorkspaceIndexDirs.empty(),
}) async {
  final chat = _RecordingChatCubit();
  addTearDown(chat.close);
  late BuildContext captured;
  // Production wraps MaterialApp.router itself with the bloc providers, so
  // dialogs (built in the root navigator's overlay) can read them — mirror
  // that structure here.
  await tester.pumpWidget(
    MultiRepositoryProvider(
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
  );
  // The open future only completes on pop, so it must not be awaited here —
  // callers settle the entrance animation instead.
  unawaited(
    editWorkspaceQuickOpenScope(
      captured,
      Workspace(
        workspaceId: 'ws1',
        folders: const [WorkspaceFolder(path: '/repo')],
        createdAt: 1,
        indexDirRules: initial,
      ),
    ),
  );
  return chat;
}

/// Drains the AppToast auto-dismiss timer so the test tree ends clean.
Future<void> _drainToast(WidgetTester tester, {int seconds = 4}) async {
  await tester.pump(Duration(seconds: seconds));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _closeDialog(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.close_rounded).at(0));
  await tester.pumpAndSettle();
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  // FilePicker.platform is a global static normally set by plugin
  // registration; capture-and-restore keeps the fake scoped to one test.
  FilePicker? originalFilePicker;
  setUp(() {
    try {
      originalFilePicker = FilePicker.platform;
    } on Object {
      originalFilePicker = null;
    }
  });
  tearDown(() {
    final original = originalFilePicker;
    if (original != null) FilePicker.platform = original;
  });

  Finder addField(int index) =>
      find.widgetWithText(TextField, l10n.workspaceQuickOpenScopeAddPathHint)
          .at(index);

  testWidgets('renders sections and existing rules without warnings', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      initial: WorkspaceIndexDirs(
        excluded: ['common'],
        included: ['common/convertor'],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.workspaceQuickOpenScopeExcludedTitle), findsOneWidget);
    expect(find.text(l10n.workspaceQuickOpenScopeIncludedTitle), findsOneWidget);
    expect(find.text(l10n.workspaceQuickOpenScopeAutoSave), findsOneWidget);
    expect(find.text('common'), findsOneWidget);
    expect(find.text('common/convertor'), findsOneWidget);
    expect(find.text(l10n.workspaceQuickOpenScopeOrphanInclude), findsNothing);

    await _closeDialog(tester);
  });

  testWidgets('every add and remove persists immediately', (tester) async {
    final chat = await _pumpDialog(
      tester,
      initial: WorkspaceIndexDirs(excluded: ['common']),
    );
    await tester.pumpAndSettle();

    await tester.enterText(addField(0), 'logs');
    await tester.tap(find.byIcon(Icons.add_rounded).at(0));
    await tester.pump();
    expect(find.text('logs'), findsOneWidget);
    expect(chat.savedRules, [
      WorkspaceIndexDirs(excluded: ['common', 'logs']),
    ]);

    // Remove it again — index 0 is the dialog header's close, 1 the row.
    await tester.tap(find.byIcon(Icons.close_rounded).at(2));
    await tester.pump();
    expect(find.text('logs'), findsNothing);
    expect(chat.savedRules, [
      WorkspaceIndexDirs(excluded: ['common', 'logs']),
      WorkspaceIndexDirs(excluded: ['common']),
    ]);

    await tester.enterText(addField(0), 'vendor');
    await tester.tap(find.byIcon(Icons.add_rounded).at(0));
    await tester.pump();
    expect(chat.savedRules.last, WorkspaceIndexDirs(
      excluded: ['common', 'vendor'],
    ));

    // Closing never re-persists and never discards — the last persist stands.
    await _closeDialog(tester);
    expect(chat.savedRules.length, 3);
  });

  testWidgets('duplicate adds are rejected with a warning toast', (
    tester,
  ) async {
    final chat = await _pumpDialog(
      tester,
      initial: WorkspaceIndexDirs(excluded: ['common']),
    );
    await tester.pumpAndSettle();

    await tester.enterText(addField(0), 'common');
    await tester.tap(find.byIcon(Icons.add_rounded).at(0));
    await tester.pump();
    expect(find.text(l10n.workspaceQuickOpenScopeDuplicate), findsOneWidget);
    await _drainToast(tester);
    // Header close + the single row's remove button — the rejected add must
    // not have produced a second row or a persist.
    expect(find.byIcon(Icons.close_rounded), findsNWidgets(2));
    expect(chat.savedRules, isEmpty);

    await _closeDialog(tester);
  });

  testWidgets('cross-list duplicates are rejected too', (tester) async {
    final chat = await _pumpDialog(
      tester,
      initial: WorkspaceIndexDirs(excluded: ['common']),
    );
    await tester.pumpAndSettle();

    await tester.enterText(addField(1), 'common');
    await tester.tap(find.byIcon(Icons.add_rounded).at(1));
    await tester.pump();
    expect(find.text(l10n.workspaceQuickOpenScopeDuplicate), findsOneWidget);
    await _drainToast(tester);
    expect(chat.savedRules, isEmpty);

    await _closeDialog(tester);
  });

  testWidgets('orphan include rows carry a no-effect warning', (tester) async {
    await _pumpDialog(
      tester,
      initial: WorkspaceIndexDirs(
        excluded: ['common'],
        included: ['elsewhere', 'common/convertor'],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.workspaceQuickOpenScopeOrphanInclude), findsOneWidget);

    await _closeDialog(tester);
  });

  testWidgets('typed paths are normalized before persisting', (tester) async {
    final chat = await _pumpDialog(tester);
    await tester.pumpAndSettle();

    await tester.enterText(addField(0), './common//');
    await tester.tap(find.byIcon(Icons.add_rounded).at(0));
    await tester.pump();
    expect(find.text('common'), findsOneWidget);
    expect(chat.savedRules, [WorkspaceIndexDirs(excluded: ['common'])]);

    await _closeDialog(tester);
  });

  testWidgets('a failed persist rolls the row back and toasts the error', (
    tester,
  ) async {
    final chat = await _pumpDialog(
      tester,
      initial: WorkspaceIndexDirs(excluded: ['common']),
    );
    await tester.pumpAndSettle();

    chat.failNextWith = StateError('disk full');
    await tester.enterText(addField(0), 'logs');
    await tester.tap(find.byIcon(Icons.add_rounded).at(0));
    // First pump builds the optimistic row; the persist failure lands as a
    // microtask and the second pump builds the rolled-back tree + toast.
    await tester.pump();
    await tester.pump();
    // The optimistic row rolled back once the persist threw; the typed text
    // survives so the user can retry.
    expect(find.text('logs'), findsOneWidget);
    expect(chat.savedRules, isEmpty);
    expect(
      find.text(l10n.workspaceQuickOpenScopeSaveFailed('Bad state: disk full')),
      findsOneWidget,
    );
    await _drainToast(tester, seconds: 5);

    // The rolled-back rules are untouched.
    expect(find.text('common'), findsOneWidget);

    await _closeDialog(tester);
  });

  // Export/import drive real file IO through dart:io, so they run inside
  // runAsync (the repo's established pattern) with a short real delay letting
  // the pending write/read complete before the next frame.
  testWidgets('export writes the current rules to the picked file', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('scope_export_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final targetPath = '${tmp.path}/search-scope.json';
      final picker = _FakeFilePicker()..savePath = targetPath;
      FilePicker.platform = picker;

      await _pumpDialog(
        tester,
        initial: WorkspaceIndexDirs(
          excluded: ['common'],
          included: ['common/convertor'],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.file_upload_outlined));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      final decoded = jsonDecode(await File(targetPath).readAsString());
      expect(decoded, {
        'excluded': ['common'],
        'included': ['common/convertor'],
      });
      // No display name set → first folder's basename seeds the default name.
      expect(picker.lastSaveFileName, 'repo-search-scope.json');
      expect(
        find.text(l10n.workspaceQuickOpenScopeExportSuccess),
        findsOneWidget,
      );
      // The toast engine tears its overlay entry down on a real timer (exit
      // animation + removal delay ≈ 250ms); fake pumps can't advance it inside
      // runAsync, so wait it out — a stale entry would swallow the next test's
      // toast into a dead overlay.
      AppToast.dismiss();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();

      await _closeDialog(tester);
    });
  });

  testWidgets('export aborted in the save dialog writes nothing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final picker = _FakeFilePicker(); // saveFile answers null (aborted)
      FilePicker.platform = picker;

      await _pumpDialog(tester, initial: WorkspaceIndexDirs(excluded: ['a']));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.file_upload_outlined));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();

      expect(picker.lastSaveFileName, 'repo-search-scope.json');
      expect(
        find.text(l10n.workspaceQuickOpenScopeExportSuccess),
        findsNothing,
      );

      await _closeDialog(tester);
    });
  });

  testWidgets('import replaces both lists and persists immediately', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('scope_import_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final sourcePath = '${tmp.path}/search-scope.json';
      File(sourcePath).writeAsStringSync(
        jsonEncode({
          'excluded': ['logs', 'build'],
          'included': ['logs/sub'],
        }),
      );
      final picker = _FakeFilePicker()..pickPath = sourcePath;
      FilePicker.platform = picker;

      final chat = await _pumpDialog(
        tester,
        initial: WorkspaceIndexDirs(excluded: ['common']),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.file_download_outlined));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('logs'), findsOneWidget);
      expect(find.text('build'), findsOneWidget);
      expect(find.text('logs/sub'), findsOneWidget);
      expect(find.text('common'), findsNothing);
      expect(chat.savedRules, [
        WorkspaceIndexDirs(excluded: ['logs', 'build'], included: ['logs/sub']),
      ]);
      expect(
        find.text(l10n.workspaceQuickOpenScopeImportSuccess),
        findsOneWidget,
      );
      // Same engine teardown wait as the export test above.
      AppToast.dismiss();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();

      await _closeDialog(tester);
    });
  });

  testWidgets('importing a non-scope file is rejected without persisting', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final tmp = await Directory.systemTemp.createTemp('scope_import_bad_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final sourcePath = '${tmp.path}/search-scope.json';
      File(sourcePath).writeAsStringSync('{"keybindings": {}}');
      final picker = _FakeFilePicker()..pickPath = sourcePath;
      FilePicker.platform = picker;

      final chat = await _pumpDialog(
        tester,
        initial: WorkspaceIndexDirs(excluded: ['common']),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.file_download_outlined));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('common'), findsOneWidget);
      expect(chat.savedRules, isEmpty);
      expect(
        find.text(l10n.workspaceQuickOpenScopeImportInvalid),
        findsOneWidget,
      );
      // Same engine teardown wait as the export test above.
      AppToast.dismiss();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();

      await _closeDialog(tester);
    });
  });
}
