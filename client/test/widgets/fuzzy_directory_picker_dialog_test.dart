import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/workspace_directory_picker.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/widgets/fuzzy_directory_picker_dialog.dart';

/// Fakes only what the dialog touches: a home, one level of folders, and
/// `RemoteDirectoryBrowser`'s stat/listDir/pathContext needs.
class _FakeFilesystem implements Filesystem {
  _FakeFilesystem({required this.home, required this.entries});

  final String home;

  /// dir path -> child entries.
  final Map<String, List<FsDirEntry>> entries;

  @override
  final p.Context pathContext = p.Context(style: p.Style.posix);

  @override
  Future<String?> resolveSymlink(String path) async =>
      path == '.' ? home : path;

  @override
  Future<FsStat> stat(String path) async {
    if (entries.containsKey(path)) {
      return const FsStat(kind: FsEntityKind.directory);
    }
    return const FsStat(kind: FsEntityKind.notFound);
  }

  @override
  Future<List<FsDirEntry>> listDir(String path) async =>
      entries[path] ?? const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late _FakeFilesystem fs;
  late WorkspaceDirectoryPicker picker;

  setUp(() {
    fs = _FakeFilesystem(
      home: '/home/alice',
      entries: {
        '/home/alice': [
          for (final name in [
            'Documents',
            'Downloads',
            'dev',
            'teampilot',
            '.hidden',
          ])
            FsDirEntry(name: name, isDirectory: true),
        ],
        '/home/alice/dev': const [],
      },
    );
    picker = WorkspaceDirectoryPicker(
      resolveContext: (_) async => RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: fs,
        home: '/home/alice',
        cwd: '/home/alice',
        appDataRoot: '/home/alice/.local/share/teampilot-test',
        paths: AppPaths('/home/alice/.local/share/teampilot-test'),
      ),
      listTargets: () async => const [],
    );
  });

  Future<void> pump(WidgetTester tester, {String? initialPath}) async {
    final theme = ThemeData.light();
    await tester.pumpWidget(
      RepositoryProvider<WorkspaceDirectoryPicker>.value(
        value: picker,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: theme,
          home: TpTheme(
            data: TpThemeData.fromColorScheme(
              theme.colorScheme,
              scale: 1.0,
              controlScale: AppTypographyScale.standard.multiplier,
            ),
            child: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showFuzzyDirectoryPickerDialog(
                    context,
                    targetId: 'local',
                    initialPath: initialPath,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists the start directory with hidden folders filtered',
      (tester) async {
    await pump(tester);

    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('dev'), findsOneWidget);
    expect(find.text('.hidden'), findsNothing);
  });

  testWidgets('fuzzy filter narrows the folder list and highlights matches',
      (tester) async {
    await pump(tester);

    await tester.enterText(
      find.byType(TextField),
      'tp',
    );
    await tester.pumpAndSettle();

    // Only the fuzzy subsequence match survives: "teampilot" (t…p…).
    expect(find.text('teampilot'), findsOneWidget);
    expect(find.text('Documents'), findsNothing);
    expect(find.text('Downloads'), findsNothing);
  });

  testWidgets('no match shows the empty hint instead of a blank list',
      (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();

    expect(find.text('No folders match'), findsOneWidget);
  });

  testWidgets('tapping a folder navigates into it and clears the filter',
      (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'dev');
    await tester.pumpAndSettle();
    // The list tile, not the filter field's own text.
    await tester.tap(find.text('dev').last);
    await tester.pumpAndSettle();

    expect(find.text('/home/alice/dev'), findsOneWidget);
  });

  testWidgets('"use this directory" returns the current path', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Use this directory'));
    await tester.pumpAndSettle();

    expect(find.byType(FuzzyDirectoryPickerDialog), findsNothing);
  });
}
