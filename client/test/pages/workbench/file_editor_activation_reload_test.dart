import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/pages/workbench/file_editor_surface.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/services/editor/markdown_view_mode_store.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';

import '../../support/in_memory_filesystem.dart';

const _ws = 'ws-activation';

void main() {
  /// Mounts the file surface (or a placeholder) the way the workbench body
  /// does: only the active tab's surface is in the tree.
  Widget hostFor({
    required EditorCubit editor,
    required WorkbenchCubit workbench,
    required WorkbenchEditorOpener opener,
    required Widget child,
  }) {
    final theme = ThemeData(useMaterial3: true);
    return TpTheme(
      data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: theme,
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: editor),
              BlocProvider.value(value: workbench),
            ],
            child: MultiRepositoryProvider(
              providers: [
                RepositoryProvider.value(value: opener),
                RepositoryProvider<CommandBus>(create: (_) => CommandBus()),
              ],
              child: Center(
                child: SizedBox(width: 800, height: 400, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }

  ({EditorCubit editor, WorkbenchCubit workbench, WorkbenchEditorOpener opener})
  harness({
    required InMemoryFilesystem fs,
    required bool Function() reloadOnTabActivate,
  }) {
    final editor = EditorCubit(
      fs: fs,
      reloadOnTabActivate: reloadOnTabActivate,
    );
    final workbench = WorkbenchCubit();
    final opener = WorkbenchEditorOpener(
      editor: editor,
      workbench: workbench,
      markdownViewModes: MarkdownViewModeStore(),
      readMarkdownOpenMode: () => MarkdownOpenMode.preview,
      readEditorPreviewTabs: () => true,
    );
    return (editor: editor, workbench: workbench, opener: opener);
  }

  testWidgets('re-activating a clean file tab re-reads it from disk', (
    tester,
  ) async {
    final fs = InMemoryFilesystem();
    const path = '/repo/a.txt';
    fs.files[path] = 'v1';
    final h = harness(fs: fs, reloadOnTabActivate: () => true);
    addTearDown(h.editor.close);
    addTearDown(h.workbench.close);
    await h.editor.openFile(_ws, path);

    Widget surface() => hostFor(
      editor: h.editor,
      workbench: h.workbench,
      opener: h.opener,
      child: const FileEditorSurface(workspaceId: _ws, path: path),
    );

    await tester.pumpWidget(surface());
    await tester.pumpAndSettle();
    expect(h.editor.controllerFor(_ws, path)?.text, 'v1');

    // Another tab becomes active: the file surface leaves the tree.
    await tester.pumpWidget(
      hostFor(
        editor: h.editor,
        workbench: h.workbench,
        opener: h.opener,
        child: const SizedBox(),
      ),
    );
    await tester.pumpAndSettle();

    // External edit while the tab was inactive.
    fs.files[path] = 'v2';

    // Switching back refreshes the buffer once.
    await tester.pumpWidget(surface());
    await tester.pumpAndSettle();
    expect(h.editor.controllerFor(_ws, path)?.text, 'v2');
    expect(h.editor.state.bucket(_ws).isDirty(path), isFalse);
  });

  testWidgets('unsaved edits survive re-activation', (tester) async {
    final fs = InMemoryFilesystem();
    const path = '/repo/b.txt';
    fs.files[path] = 'v1';
    final h = harness(fs: fs, reloadOnTabActivate: () => true);
    addTearDown(h.editor.close);
    addTearDown(h.workbench.close);
    await h.editor.openFile(_ws, path);
    h.editor.controllerFor(_ws, path)!.text = 'mine';
    await tester.pumpAndSettle();

    Widget surface() => hostFor(
      editor: h.editor,
      workbench: h.workbench,
      opener: h.opener,
      child: const FileEditorSurface(workspaceId: _ws, path: path),
    );

    await tester.pumpWidget(surface());
    await tester.pumpAndSettle();
    fs.files[path] = 'v2';

    await tester.pumpWidget(
      hostFor(
        editor: h.editor,
        workbench: h.workbench,
        opener: h.opener,
        child: const SizedBox(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(surface());
    await tester.pumpAndSettle();

    expect(h.editor.controllerFor(_ws, path)?.text, 'mine');
    expect(h.editor.state.bucket(_ws).isDirty(path), isTrue);
  });

  testWidgets('preference off keeps the buffer untouched on re-activation', (
    tester,
  ) async {
    final fs = InMemoryFilesystem();
    const path = '/repo/c.txt';
    fs.files[path] = 'v1';
    final h = harness(fs: fs, reloadOnTabActivate: () => false);
    addTearDown(h.editor.close);
    addTearDown(h.workbench.close);
    await h.editor.openFile(_ws, path);

    await tester.pumpWidget(
      hostFor(
        editor: h.editor,
        workbench: h.workbench,
        opener: h.opener,
        child: const FileEditorSurface(workspaceId: _ws, path: path),
      ),
    );
    await tester.pumpAndSettle();
    fs.files[path] = 'v2';

    await tester
        .pumpWidget(
          hostFor(
            editor: h.editor,
            workbench: h.workbench,
            opener: h.opener,
            child: const SizedBox(),
          ),
        )
        .then((_) => tester.pumpAndSettle());
    await tester.pumpWidget(
      hostFor(
        editor: h.editor,
        workbench: h.workbench,
        opener: h.opener,
        child: const FileEditorSurface(workspaceId: _ws, path: path),
      ),
    );
    await tester.pumpAndSettle();

    expect(h.editor.controllerFor(_ws, path)?.text, 'v1');
  });
}