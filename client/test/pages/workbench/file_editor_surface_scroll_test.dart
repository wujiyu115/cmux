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

import '../../services/editor_platform/fake_ts_worker.dart';
import '../../support/in_memory_filesystem.dart';

const _ws = 'ws-scroll';

Widget _host({
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

/// The single vertical [Scrollable] of the mounted editor pane (re-editor's
/// code field, or the markdown preview's scroll view).
ScrollableState _verticalScrollable(WidgetTester tester) => tester.state(
  find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  ),
);

ScrollableState _horizontalScrollable(WidgetTester tester) => tester.state(
  find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
  ),
);

void main() {
  testWidgets(
    'code editor restores vertical and horizontal scroll after remount',
    (tester) async {
      final fs = InMemoryFilesystem();
      const path = '/repo/long.txt';
      fs.files[path] = List.generate(
        400,
        (i) => List.filled(300, 'x').join(),
      ).join('\n');

      final editor = EditorCubit(fs: fs);
      final workbench = WorkbenchCubit();
      final modes = MarkdownViewModeStore();
      final opener = WorkbenchEditorOpener(
        editor: editor,
        workbench: workbench,
        markdownViewModes: modes,
        readMarkdownOpenMode: () => MarkdownOpenMode.preview,
        readEditorPreviewTabs: () => true,
      );
      addTearDown(editor.close);
      addTearDown(workbench.close);
      await editor.openFile(_ws, path);

      Widget hostFor(Widget child) => _host(
        editor: editor,
        workbench: workbench,
        opener: opener,
        child: child,
      );

      await tester.pumpWidget(
        hostFor(const FileEditorSurface(workspaceId: _ws, path: path)),
      );
      await tester.pumpAndSettle();

      _verticalScrollable(tester).position.jumpTo(600);
      _horizontalScrollable(tester).position.jumpTo(80);
      await tester.pumpAndSettle();
      expect(
        editor.codeScrollOffsetFor(_ws, path),
        (vertical: 600.0, horizontal: 80.0),
      );

      // Switching to another tab unmounts the surface.
      await tester.pumpWidget(hostFor(const SizedBox()));
      await tester.pumpAndSettle();

      // Switching back remounts it with the retained viewport.
      await tester.pumpWidget(
        hostFor(const FileEditorSurface(workspaceId: _ws, path: path)),
      );
      await tester.pumpAndSettle();

      expect(_verticalScrollable(tester).position.pixels, 600.0);
      expect(_horizontalScrollable(tester).position.pixels, 80.0);
      expect(editor.controllerFor(_ws, path)?.text, fs.files[path]);
    },
  );

  testWidgets(
    'markdown preview scroll is restored and independent of source mode',
    (tester) async {
      final fs = InMemoryFilesystem();
      const path = '/repo/doc.md';
      fs.files[path] = List.generate(
        120,
        (i) => '## Paragraph $i\n\nSome text here.',
      ).join('\n\n');

      final editor = EditorCubit(fs: fs, workerPool: FakeTsWorkerPool());
      final workbench = WorkbenchCubit();
      final modes = MarkdownViewModeStore();
      final opener = WorkbenchEditorOpener(
        editor: editor,
        workbench: workbench,
        markdownViewModes: modes,
        readMarkdownOpenMode: () => MarkdownOpenMode.preview,
        readEditorPreviewTabs: () => true,
      );
      addTearDown(editor.close);
      addTearDown(workbench.close);
      // Markdown is a highlightable language, so opening awaits worker
      // replies delivered as zero-duration timers — which only fire on the
      // real event loop. Run the open inside runAsync (FakeAsync's clock does
      // not advance while we await it here).
      await tester.runAsync(() => editor.openFile(_ws, path));

      Widget hostFor(Widget child) => _host(
        editor: editor,
        workbench: workbench,
        opener: opener,
        child: child,
      );

      // Markdown files default to preview mode.
      await tester.pumpWidget(
        hostFor(const FileEditorSurface(workspaceId: _ws, path: path)),
      );
      await tester.pumpAndSettle();

      _verticalScrollable(tester).position.jumpTo(300);
      await tester.pumpAndSettle();
      expect(editor.markdownPreviewScrollOffsetFor(_ws, path), 300.0);

      await tester.pumpWidget(hostFor(const SizedBox()));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        hostFor(const FileEditorSurface(workspaceId: _ws, path: path)),
      );
      await tester.pumpAndSettle();
      expect(_verticalScrollable(tester).position.pixels, 300.0);

      // Source mode keeps its own anchor.
      modes.setMode(path, MarkdownViewMode.source);
      await tester.pumpAndSettle();
      _verticalScrollable(tester).position.jumpTo(120);
      await tester.pumpAndSettle();
      expect(editor.codeScrollOffsetFor(_ws, path).vertical, 120.0);
      expect(editor.markdownPreviewScrollOffsetFor(_ws, path), 300.0);

      // Back to preview: the preview offset is the one restored.
      modes.setMode(path, MarkdownViewMode.preview);
      await tester.pumpAndSettle();
      expect(_verticalScrollable(tester).position.pixels, 300.0);
    },
  );

  testWidgets('oversized anchor clamps to the content, not past it', (
    tester,
  ) async {
    final fs = InMemoryFilesystem();
    const path = '/repo/short.txt';
    fs.files[path] = 'one\ntwo\nthree';

    final editor = EditorCubit(fs: fs);
    final workbench = WorkbenchCubit();
    final modes = MarkdownViewModeStore();
    final opener = WorkbenchEditorOpener(
      editor: editor,
      workbench: workbench,
      markdownViewModes: modes,
      readMarkdownOpenMode: () => MarkdownOpenMode.preview,
      readEditorPreviewTabs: () => true,
    );
    addTearDown(editor.close);
    addTearDown(workbench.close);
    await editor.openFile(_ws, path);
    editor.setCodeScrollOffset(_ws, path, vertical: 5000);

    await tester.pumpWidget(
      _host(
        editor: editor,
        workbench: workbench,
        opener: opener,
        child: const FileEditorSurface(workspaceId: _ws, path: path),
      ),
    );
    await tester.pumpAndSettle();

    expect(_verticalScrollable(tester).position.pixels, lessThan(5000));
  });
}
