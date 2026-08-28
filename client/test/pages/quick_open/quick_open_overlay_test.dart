import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
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

InMemoryFilesystem _fs() {
  final fs = InMemoryFilesystem();
  fs.ensureDir('/repo/lib');
  fs.ensureDir('/repo/docs');
  fs.files['/repo/lib/main.dart'] = 'x';
  fs.files['/repo/lib/terminal_session.dart'] = 'x';
  fs.files['/repo/docs/README.md'] = 'x';
  return fs;
}

class _DialogResult {
  String? value;
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
            result.value = await showDialog<String>(
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

    final result = await _pumpDialog(
      tester,
      QuickOpenOverlay(
        workspace: _workspace(),
        filesystem: fs,
        indexRegistry: QuickOpenIndexRegistry(),
        mruRepository: mru,
      ),
    );

    expect(find.text('Recently opened'), findsOneWidget);
    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('lib/main.dart'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result.value, '/repo/lib/main.dart');
  });

  testWidgets('typing filters by fuzzy match and Enter opens the file', (
    tester,
  ) async {
    final fs = _fs();
    final result = await _pumpDialog(
      tester,
      QuickOpenOverlay(
        workspace: _workspace(),
        filesystem: fs,
        indexRegistry: QuickOpenIndexRegistry(),
        mruRepository: QuickOpenMruRepository(fs: fs, path: '/mru.json'),
      ),
    );
    expect(result.value, isNull); // not closed yet

    await tester.enterText(find.byType(TextField), 'read');
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('docs/README.md'), findsOneWidget);
    expect(find.text('main.dart'), findsNothing);
    expect(find.text('terminal_session.dart'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(result.value, '/repo/docs/README.md');
    expect(find.byType(QuickOpenOverlay), findsNothing);
  });

  testWidgets('no matching files shows the empty state', (tester) async {
    final fs = _fs();
    await _pumpDialog(
      tester,
      QuickOpenOverlay(
        workspace: _workspace(),
        filesystem: fs,
        indexRegistry: QuickOpenIndexRegistry(),
        mruRepository: QuickOpenMruRepository(fs: fs, path: '/mru.json'),
      ),
    );

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('No matching files'), findsOneWidget);
  });

  testWidgets('Esc closes without opening', (tester) async {
    final fs = _fs();
    final result = await _pumpDialog(
      tester,
      QuickOpenOverlay(
        workspace: _workspace(),
        filesystem: fs,
        indexRegistry: QuickOpenIndexRegistry(),
        mruRepository: QuickOpenMruRepository(fs: fs, path: '/mru.json'),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(result.value, isNull);
    expect(find.byType(QuickOpenOverlay), findsNothing);
  });
}
