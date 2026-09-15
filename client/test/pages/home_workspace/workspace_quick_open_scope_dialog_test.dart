import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_index_dirs.dart';
import 'package:teampilot/pages/home_workspace/workspace_quick_open_scope_dialog.dart';

/// Pumps a bare app, opens the scope dialog over [initial] rules, and returns
/// its result future. Callers settle the dialog open animation themselves.
///
/// Icon finders line up with section order (exclude = 0, include = 1); the
/// dialog header's own close button is [Icons.close_rounded] index 0, so row
/// remove buttons start at index 1.
Future<Future<WorkspaceIndexDirs?>> _pumpDialog(
  WidgetTester tester, {
  WorkspaceIndexDirs initial = const WorkspaceIndexDirs.empty(),
}) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
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
  );
  return showWorkspaceQuickOpenScopeDialog(
    captured,
    workspace: Workspace(
      workspaceId: 'ws1',
      folders: const [WorkspaceFolder(path: '/repo')],
      createdAt: 1,
      indexDirRules: initial,
    ),
  );
}

/// Drains the AppToast auto-dismiss timer so the test tree ends clean.
Future<void> _drainToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  Finder addField(int index) =>
      find.widgetWithText(TextField, l10n.workspaceQuickOpenScopeAddPathHint)
          .at(index);

  testWidgets('renders sections and existing rules without warnings', (
    tester,
  ) async {
    final future = await _pumpDialog(
      tester,
      initial: WorkspaceIndexDirs(
        excluded: ['common'],
        included: ['common/convertor'],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.workspaceQuickOpenScopeExcludedTitle), findsOneWidget);
    expect(find.text(l10n.workspaceQuickOpenScopeIncludedTitle), findsOneWidget);
    expect(find.text('common'), findsOneWidget);
    expect(find.text('common/convertor'), findsOneWidget);
    expect(find.text(l10n.workspaceQuickOpenScopeOrphanInclude), findsNothing);

    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(await future, isNull);
  });

  testWidgets('adds, removes and saves edited rules', (tester) async {
    final future = await _pumpDialog(
      tester,
      initial: WorkspaceIndexDirs(excluded: ['common']),
    );
    await tester.pumpAndSettle();

    await tester.enterText(addField(0), 'logs');
    await tester.tap(find.byIcon(Icons.add_rounded).at(0));
    await tester.pump();
    expect(find.text('logs'), findsOneWidget);

    // Remove it again — index 0 is the dialog header's close, 1 the row.
    await tester.tap(find.byIcon(Icons.close_rounded).at(2));
    await tester.pump();
    expect(find.text('logs'), findsNothing);

    await tester.enterText(addField(0), 'vendor');
    await tester.tap(find.byIcon(Icons.add_rounded).at(0));
    await tester.pump();

    await tester.tap(find.text(l10n.save));
    await tester.pumpAndSettle();
    expect(
      await future,
      WorkspaceIndexDirs(excluded: ['common', 'vendor']),
    );
  });

  testWidgets('duplicate adds are rejected with a warning toast', (
    tester,
  ) async {
    final future = await _pumpDialog(
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
    // not have produced a second row.
    expect(find.byIcon(Icons.close_rounded), findsNWidgets(2));

    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(await future, isNull);
  });

  testWidgets('cross-list duplicates are rejected too', (tester) async {
    await _pumpDialog(
      tester,
      initial: WorkspaceIndexDirs(excluded: ['common']),
    );
    await tester.pumpAndSettle();

    await tester.enterText(addField(1), 'common');
    await tester.tap(find.byIcon(Icons.add_rounded).at(1));
    await tester.pump();
    expect(find.text(l10n.workspaceQuickOpenScopeDuplicate), findsOneWidget);
    await _drainToast(tester);

    await tester.tap(find.byIcon(Icons.close_rounded).at(0));
    await tester.pumpAndSettle();
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

    await tester.tap(find.byIcon(Icons.close_rounded).at(0));
    await tester.pumpAndSettle();
  });

  testWidgets('typed paths are normalized before entering the list', (
    tester,
  ) async {
    final future = await _pumpDialog(tester);
    await tester.pumpAndSettle();

    await tester.enterText(addField(0), './common//');
    await tester.tap(find.byIcon(Icons.add_rounded).at(0));
    await tester.pump();
    expect(find.text('common'), findsOneWidget);

    await tester.tap(find.text(l10n.save));
    await tester.pumpAndSettle();
    expect(await future, WorkspaceIndexDirs(excluded: ['common']));
  });
}
