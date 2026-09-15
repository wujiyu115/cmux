import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell_tabs.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );
}

Future<void> _openContextMenu(WidgetTester tester) async {
  final chip = find.byType(WorkspaceShellTabChip);
  await tester.tap(chip, buttons: kSecondaryButton);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(AppToast.dismiss);

  testWidgets('file tab menu shows reveal-in-tree and toasts on failure',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        WorkspaceShellTabChip(
          title: 'role.td',
          active: true,
          filePath: '/repo/static/schema/role.td',
          workspaceId: 'ws-1',
          onTap: () {},
          onClose: () {},
        ),
      ),
    );

    await _openContextMenu(tester);

    expect(find.text('Reveal in file tree'), findsOneWidget);
    // No WorkspaceToolsScope in this bare harness → reveal fails and the
    // shared failure toast appears.
    await tester.tap(find.text('Reveal in file tree'));
    await tester.pumpAndSettle();
    expect(find.text('Cannot reveal this file in the file tree'),
        findsOneWidget);
    // Error toasts auto-close on a 5s timer; advance past it so no timer
    // outlives the test.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('file tab without workspaceId omits reveal-in-tree',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        WorkspaceShellTabChip(
          title: 'role.td',
          active: true,
          filePath: '/repo/static/schema/role.td',
          onTap: () {},
          onClose: () {},
        ),
      ),
    );

    await _openContextMenu(tester);

    expect(find.text('Reveal in file tree'), findsNothing);
  });

  testWidgets('session tab menu omits reveal-in-tree', (tester) async {
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

    await _openContextMenu(tester);

    expect(find.text('Reveal in file tree'), findsNothing);
  });
}
