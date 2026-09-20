import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:teampilot/widgets/workbench/code_find_panel.dart';

import '../../support/in_memory_filesystem.dart';

const _ws = 'ws-focus';

/// Regression: a file opened while another surface held focus (Ctrl+P quick
/// open, search panel, terminal link) must land with the editor focused, so
/// editor-scoped shortcuts — Ctrl+F above all — work without first clicking
/// the file content. Before the fix the pane's re-editor autofocus was
/// discarded (the enclosing scope already had a focused child from the
/// pre-open surface) and Ctrl+F fell through to nothing.
void main() {
  testWidgets(
    'file opened via opener takes focus; Ctrl+F opens the find panel',
    (tester) async {
      final fs = InMemoryFilesystem();
      const path = '/repo/a.txt';
      fs.files[path] = 'one\ntwo\nthree';

      final editor = EditorCubit(fs: fs);
      final workbench = WorkbenchCubit();
      final opener = WorkbenchEditorOpener(
        editor: editor,
        workbench: workbench,
        markdownViewModes: MarkdownViewModeStore(),
        readMarkdownOpenMode: () => MarkdownOpenMode.preview,
        readEditorPreviewTabs: () => true,
      );
      final theme = ThemeData(useMaterial3: true);
      Widget host({required bool showEditor}) => TpTheme(
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
                  RepositoryProvider<CommandBus>(
                    create: (_) => CommandBus(),
                  ),
                ],
                child: Builder(
                  builder: (context) => Stack(
                    children: [
                      // Stand-in for the workspace shell terminal: it stays
                      // MOUNTED (attached to the focus tree) when the file
                      // tab activates — the workbench body stack keeps the
                      // shell pane offstage, not unmounted. Its focused node
                      // therefore blocks the editor pane's autofocus.
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: SizedBox(
                          width: 200,
                          height: 48,
                          child: TextField(
                            focusNode: FocusNode(debugLabel: 'pre-open'),
                          ),
                        ),
                      ),
                      if (showEditor)
                        Positioned.fill(
                          child: FileEditorSurface(
                            workspaceId: _ws,
                            path: path,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Pre-open state: only the focus-holding surface is mounted.
      await tester.pumpWidget(host(showEditor: false));
      await tester.pumpAndSettle();

      // Focus sits on the pre-open surface, like a terminal before Ctrl+P.
      tester
          .widget<TextField>(find.byType(TextField))
          .focusNode!
          .requestFocus();
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus,
        tester.widget<TextField>(find.byType(TextField)).focusNode,
      );

      // Ctrl+P: a dialog route takes focus (its own scope), then pops and
      // restores focus to the pre-open surface. This round-trip is what
      // makes the pane's later autofocus lose: after a real focus scope
      // restore, the enclosing scope's focusedChild is the terminal's node,
      // so the editor's autofocus request is discarded.
      final shellContext = tester.state(find.byType(Scaffold)).context;
      Navigator.of(shellContext).push(
        DialogRoute<void>(
          context: shellContext,
          builder: (context) => const AlertDialog(title: Text('quick open')),
        ),
      );
      await tester.pumpAndSettle();
      Navigator.of(shellContext).pop();
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus,
        tester.widget<TextField>(find.byType(TextField)).focusNode,
      );

      // Quick-open's open path: activate the tab, load — the workbench now
      // mounts the editor surface (center pane mounts on tab activation).
      await opener.openFile(_ws, path, fs: fs, preview: true);
      await tester.pumpWidget(host(showEditor: true));
      await tester.pumpAndSettle();

      final editorFocus = tester.widget<Focus>(
        find.byWidgetPredicate(
          (w) => w is Focus && w.debugLabel == 'CodeEditor',
        ),
      );
      expect(editorFocus.focusNode, isNotNull);
      expect(editorFocus.focusNode!.hasFocus, isTrue);

      // The whole point: Ctrl+F opens the editor's find panel with its input
      // focused — no click on the file content needed first.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();

      expect(find.byType(CodeFindPanel), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus,
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byType(CodeFindPanel),
                matching: find.byType(TextField),
              ),
            )
            .focusNode,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'mounted pane loses autofocus to a focused sibling — focusCodeEditor wins',
    (tester) async {
      // Minimal reproduction of the production bug (probe-verified): the
      // workbench keeps the shell terminal ATTACHED and focused while the
      // file tab activates; the newly-mounted editor pane's autofocus is
      // discarded because the enclosing scope already has a focused child.
      // Explicit focus through EditorCubit must take it back.
      final fs = InMemoryFilesystem();
      const path = '/repo/b.txt';
      fs.files[path] = 'content';

      final editor = EditorCubit(fs: fs);
      final workbench = WorkbenchCubit();
      final opener = WorkbenchEditorOpener(
        editor: editor,
        workbench: workbench,
        markdownViewModes: MarkdownViewModeStore(),
        readMarkdownOpenMode: () => MarkdownOpenMode.preview,
        readEditorPreviewTabs: () => true,
      );
      addTearDown(editor.close);
      addTearDown(workbench.close);
      await editor.openFile(_ws, path);

      final theme = ThemeData(useMaterial3: true);
      final tfNode = FocusNode(debugLabel: 'terminal');
      addTearDown(tfNode.dispose);

      Widget host({required bool showEditor}) => TpTheme(
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
                  RepositoryProvider<CommandBus>(
                    create: (_) => CommandBus(),
                  ),
                ],
                child: Column(
                  children: [
                    // Shell terminal stand-in: stays attached (workbench
                    // body keeps the shell pane mounted offstage, not
                    // unmounted) while the file pane takes the center.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 200,
                        height: 48,
                        child: TextField(focusNode: tfNode),
                      ),
                    ),
                    if (showEditor)
                      Expanded(
                        child: FileEditorSurface(
                          workspaceId: _ws,
                          path: path,
                        ),
                      )
                    else
                      const Expanded(child: SizedBox()),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(host(showEditor: false));
      tfNode.requestFocus();
      await tester.pump();
      expect(tfNode.hasFocus, isTrue);
      // File tab activates: pane mounts while the terminal still holds
      // resolved focus — re-editor's own autofocus is discarded (the
      // enclosing scope already has a focused child). The pane's explicit
      // focus claim on mount is the fix: the editor takes focus.
      await tester.pumpWidget(host(showEditor: true));
      await tester.pumpAndSettle();
      final editorFocus = tester.widget<Focus>(
        find.byWidgetPredicate(
          (w) => w is Focus && w.debugLabel == 'CodeEditor',
        ),
      );
      expect(editorFocus.focusNode!.hasFocus, isTrue);
      expect(tfNode.hasFocus, isFalse);

      // Re-claiming after the terminal re-focuses (e.g. user clicked back
      // into the shell, then re-opened the file via quick open) also works.
      tfNode.requestFocus();
      await tester.pump();
      expect(tfNode.hasFocus, isTrue);
      editor.focusCodeEditor(_ws, path);
      await tester.pumpAndSettle();
      expect(editorFocus.focusNode!.hasFocus, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
