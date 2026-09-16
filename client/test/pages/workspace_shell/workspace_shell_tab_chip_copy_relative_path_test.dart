import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell_tabs.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

Widget _wrap(Widget child, {WorkspaceToolsScopeState? scope}) {
  final tree = MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );
  if (scope == null) return tree;
  return WorkspaceToolsScope(state: scope, child: tree);
}

/// Records `Clipboard.setData` calls; the decoded argument map is
/// `Map<Object?, Object?>`, so read `text` out of it directly. Returns a
/// lazy getter because the calls land only after the menu interaction.
List<String> Function() _mockClipboard(WidgetTester tester) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      calls.add(call);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return () => [
    for (final call in calls)
      if (call.method == 'Clipboard.setData')
        (call.arguments as Map)['text'] as String,
  ];
}

Widget _fileTab(String filePath) => WorkspaceShellTabChip(
  title: 'role.td',
  active: true,
  filePath: filePath,
  workspaceId: 'ws-1',
  onTap: () {},
  onClose: () {},
);

Future<void> _openContextMenuAndCopy(WidgetTester tester) async {
  await tester.tap(find.byType(WorkspaceShellTabChip), buttons: kSecondaryButton);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Copy relative path'));
  await tester.pumpAndSettle();
}

Future<void> _settleToasts(WidgetTester tester) async {
  // Success toasts auto-close on a timer; advance past it so no timer
  // outlives the test.
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(AppToast.dismiss);

  testWidgets('copies the path relative to the scope root', (tester) async {
    final copied = _mockClipboard(tester);
    await tester.pumpWidget(
      _wrap(
        _fileTab('/repo/static/schema/role.td'),
        scope: const WorkspaceToolsScopeState(
          tools: null,
          roots: ['/repo'],
          resolving: false,
        ),
      ),
    );

    await _openContextMenuAndCopy(tester);

    expect(copied(), ['static/schema/role.td']);
    expect(find.text('Path copied: static/schema/role.td'), findsOneWidget);
    await _settleToasts(tester);
  });

  testWidgets('longest containing root wins', (tester) async {
    final copied = _mockClipboard(tester);
    await tester.pumpWidget(
      _wrap(
        _fileTab('/repo/static/schema/role.td'),
        scope: const WorkspaceToolsScopeState(
          tools: null,
          roots: ['/repo', '/repo/static'],
          resolving: false,
        ),
      ),
    );

    await _openContextMenuAndCopy(tester);

    expect(copied(), ['schema/role.td']);
    await _settleToasts(tester);
  });

  testWidgets('falls back to the absolute path outside scope roots',
      (tester) async {
    final copied = _mockClipboard(tester);
    await tester.pumpWidget(
      _wrap(
        _fileTab('/repo/AGENTS.md'),
        scope: const WorkspaceToolsScopeState(
          tools: null,
          roots: ['/elsewhere'],
          resolving: false,
        ),
      ),
    );

    await _openContextMenuAndCopy(tester);

    expect(copied(), ['/repo/AGENTS.md']);
    await _settleToasts(tester);
  });

  testWidgets('session tab menu omits copy-relative-path', (tester) async {
    await tester.pumpWidget(
      _wrap(
        WorkspaceShellTabChip(
          title: 'Chat',
          active: true,
          workspaceId: 'ws-1',
          onTap: () {},
          onClose: () {},
        ),
      ),
    );

    await tester.tap(find.byType(WorkspaceShellTabChip), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    expect(find.text('Copy relative path'), findsNothing);
  });
}
