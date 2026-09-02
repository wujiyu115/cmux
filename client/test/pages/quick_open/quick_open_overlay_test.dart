import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/quick_open/quick_open_overlay.dart';
import 'package:teampilot/services/quick_open/quick_open_index.dart';
import 'package:teampilot/services/quick_open/quick_open_mru_repository.dart';

import '../../support/in_memory_filesystem.dart';

Widget _wrap(Widget child) {
  final theme = ThemeData(useMaterial3: true);
  return TpTheme(
    data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: theme,
      home: Scaffold(body: child),
    ),
  );
}

Workspace _workspace() => Workspace(
  workspaceId: 'w1',
  folders: [WorkspaceFolder(path: '/repo')],
  createdAt: 0,
);

AppSession _session(String id, String display) => AppSession(
  sessionId: id,
  workspaceId: 'w1',
  display: display,
  createdAt: 0,
);

InMemoryFilesystem _fs() {
  final fs = InMemoryFilesystem();
  fs.ensureDir('/repo/lib');
  fs.ensureDir('/repo/docs');
  fs.files['/repo/lib/main.dart'] = 'x';
  fs.files['/repo/lib/terminal_session.dart'] = 'x';
  fs.files['/repo/docs/README.md'] = 'x';
  fs.files['/repo/docs/main.dart'] = 'x';
  return fs;
}

QuickOpenOverlay _overlay(
  InMemoryFilesystem fs, {
  QuickOpenMruRepository? mru,
  List<AppSession> sessions = const [],
}) => QuickOpenOverlay(
  workspace: _workspace(),
  filesystem: fs,
  indexRegistry: QuickOpenIndexRegistry(),
  mruRepository: mru ?? QuickOpenMruRepository(fs: fs, path: '/mru.json'),
  sessions: sessions,
  emptyTitleFallback: 'New chat',
);

class _DialogResult {
  QuickOpenResult? value;
}

/// Pumps a button that shows [overlay] in a dialog route; the returned holder
/// is filled when the dialog closes.
Future<_DialogResult> _pumpDialog(WidgetTester tester, Widget overlay) async {
  final result = _DialogResult();
  await tester.pumpWidget(
    _wrap(
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result.value = await showDialog<QuickOpenResult>(
              context: context,
              builder: (_) => overlay,
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('empty query shows recently opened files', (tester) async {
    final fs = _fs();
    final mru = QuickOpenMruRepository(fs: fs, path: '/mru.json');
    await mru.touch('/repo', '/repo/lib/main.dart');

    final result = await _pumpDialog(tester, _overlay(fs, mru: mru));

    expect(find.text('Recently opened'), findsOneWidget);
    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('lib/main.dart'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result.value, isA<QuickOpenFileResult>());
    expect((result.value! as QuickOpenFileResult).path, '/repo/lib/main.dart');
  });

  testWidgets('empty query lists recent sessions above recent files', (
    tester,
  ) async {
    final fs = _fs();
    final mru = QuickOpenMruRepository(fs: fs, path: '/mru.json');
    await mru.touch('/repo', '/repo/lib/main.dart');

    final result = await _pumpDialog(
      tester,
      _overlay(fs, mru: mru, sessions: [_session('s1', 'Deploy fix')]),
    );

    expect(find.text('Recent sessions'), findsOneWidget);
    expect(find.text('Recently opened'), findsOneWidget);
    expect(find.text('Deploy fix'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result.value, isA<QuickOpenSessionResult>());
    expect(
      (result.value! as QuickOpenSessionResult).session.sessionId,
      's1',
    );
  });

  testWidgets('a query fuzzy-matches session titles', (tester) async {
    final fs = _fs();
    final result = await _pumpDialog(
      tester,
      _overlay(fs, sessions: [_session('s1', 'Deploy fix'), _session('s2', 'Notes')]),
    );

    await tester.enterText(find.byType(TextField), 'dep');
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Deploy fix'), findsOneWidget);
    expect(find.text('Notes'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result.value, isA<QuickOpenSessionResult>());
    expect(
      (result.value! as QuickOpenSessionResult).session.sessionId,
      's1',
    );
  });

  testWidgets('typing filters by fuzzy match and Enter opens the file', (
    tester,
  ) async {
    final fs = _fs();
    final result = await _pumpDialog(tester, _overlay(fs));
    expect(result.value, isNull); // not closed yet

    await tester.enterText(find.byType(TextField), 'read');
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('docs/README.md'), findsOneWidget);
    expect(find.text('main.dart'), findsNothing);
    expect(find.text('terminal_session.dart'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect((result.value! as QuickOpenFileResult).path, '/repo/docs/README.md');
    expect(find.byType(QuickOpenOverlay), findsNothing);
  });

  testWidgets('a path query disambiguates same-named files', (tester) async {
    final fs = _fs();
    final result = await _pumpDialog(tester, _overlay(fs));

    await tester.enterText(find.byType(TextField), 'docs/main');
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('docs/main.dart'), findsOneWidget);
    expect(find.text('lib/main.dart'), findsNothing);

    // The match landed on the path, so the subtitle is what gets highlighted
    // while the basename stays plain.
    List<TextSpan> spansOf(Text text) =>
        (text.textSpan as TextSpan).children!.cast<TextSpan>();
    final nameSpans = spansOf(tester.widget<Text>(find.text('main.dart')));
    final pathSpans = spansOf(
      tester.widget<Text>(find.text('docs/main.dart')),
    );
    expect(nameSpans.map((span) => span.style).toSet().length, 1);
    expect(pathSpans.length, 'docs/main.dart'.length);
    expect(
      pathSpans.take('docs/main'.length).map((span) => span.style).toSet().length,
      1,
    );
    expect(pathSpans.last.style, isNot(pathSpans.first.style));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect((result.value! as QuickOpenFileResult).path, '/repo/docs/main.dart');
  });

  testWidgets('a basename query lists every same-named file', (tester) async {
    final fs = _fs();
    await _pumpDialog(tester, _overlay(fs));

    await tester.enterText(find.byType(TextField), 'main');
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('main.dart'), findsNWidgets(2));
    expect(find.text('lib/main.dart'), findsOneWidget);
    expect(find.text('docs/main.dart'), findsOneWidget);
  });

  testWidgets('no matching files shows the empty state', (tester) async {
    final fs = _fs();
    await _pumpDialog(tester, _overlay(fs));

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('No matching sessions or files'), findsOneWidget);
  });

  testWidgets('Esc closes without opening', (tester) async {
    final fs = _fs();
    final result = await _pumpDialog(tester, _overlay(fs));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(result.value, isNull);
    expect(find.byType(QuickOpenOverlay), findsNothing);
  });

  testWidgets('result rows do not overflow at elevated text scale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final fs = _fs();
    await _pumpDialog(tester, _overlay(fs));

    await tester.enterText(find.byType(TextField), 'read');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
