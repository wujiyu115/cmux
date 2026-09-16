import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell_tabs.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../support/in_memory_filesystem.dart';

const _ws = 'ws-1';
const _path = '/repo/static/schema/role.td';

void main() {
  late InMemoryFilesystem fs;
  late EditorCubit editor;

  setUp(() {
    fs = InMemoryFilesystem();
    fs.files[_path] = 'v1';
    editor = EditorCubit(fs: fs);
  });

  tearDown(() async {
    AppToast.dismiss();
    await editor.close();
  });

  Future<void> pumpShell(WidgetTester tester) async {
    // openFile awaits real-async work; run it before pumping, like
    // file_editor_surface_scroll_test does.
    await tester.runAsync(() => editor.openFile(_ws, _path));
    await tester.pumpWidget(
      BlocProvider<EditorCubit>.value(
        value: editor,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: WorkspaceShellTabChip(
              title: 'role.td',
              active: true,
              filePath: _path,
              workspaceId: _ws,
              onTap: () {},
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> openMenuAndRefresh(WidgetTester tester) async {
    await tester.tap(
      find.byType(WorkspaceShellTabChip),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh from disk'));
    await tester.pumpAndSettle();
  }

  testWidgets('refresh item reloads the externally changed file', (
    tester,
  ) async {
    await pumpShell(tester);
    fs.files[_path] = 'v2 — changed on disk';

    await openMenuAndRefresh(tester);

    expect(editor.controllerFor(_ws, _path)?.text, 'v2 — changed on disk');
    expect(find.text('File refreshed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('dirty buffer asks before discarding, cancel keeps edits', (
    tester,
  ) async {
    await pumpShell(tester);
    editor.controllerFor(_ws, _path)!.text = 'local edit';
    await tester.pump();
    fs.files[_path] = 'v2 — changed on disk';

    await tester.tap(
      find.byType(WorkspaceShellTabChip),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh from disk'));
    await tester.pumpAndSettle();

    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Cancelled: buffer keeps the local edit and stays dirty.
    expect(editor.controllerFor(_ws, _path)?.text, 'local edit');
    expect(editor.state.bucket(_ws).isDirty(_path), isTrue);
  });

  testWidgets('dirty buffer discards edits after confirm', (tester) async {
    await pumpShell(tester);
    editor.controllerFor(_ws, _path)!.text = 'local edit';
    await tester.pump();
    fs.files[_path] = 'v2 — changed on disk';

    await tester.tap(
      find.byType(WorkspaceShellTabChip),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh from disk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard and refresh'));
    await tester.pumpAndSettle();

    expect(editor.controllerFor(_ws, _path)?.text, 'v2 — changed on disk');
    expect(editor.state.bucket(_ws).isDirty(_path), isFalse);
    expect(find.text('File refreshed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('image tabs hide the refresh item', (tester) async {
    await tester.pumpWidget(
      BlocProvider<EditorCubit>.value(
        value: editor,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: WorkspaceShellTabChip(
              title: 'logo.png',
              active: true,
              filePath: '/repo/logo.png',
              workspaceId: _ws,
              onTap: () {},
              onClose: () {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byType(WorkspaceShellTabChip),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Refresh from disk'), findsNothing);
  });
}
