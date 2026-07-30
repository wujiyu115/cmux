import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell_tabs.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

Widget _host(Widget child) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets(
    'split mode: "+" opens the default terminal, not the launch menu',
    (tester) async {
      var defaultCalls = 0;
      var menuCalls = 0;
      await tester.pumpWidget(
        _host(
          WorkspaceShellNewChatButton(
            tooltip: 'tooltip',
            newConversationLabel: '',
            newTerminalLabel: 'New terminal',
            onNewTerminal: (_) => menuCalls++,
            onNewTerminalDefault: () => defaultCalls++,
          ),
        ),
      );

      await tester.tap(
        find.byKey(AppKeys.workspaceTabRowNewChatButton),
      );
      await tester.pump();

      expect(defaultCalls, 1);
      expect(menuCalls, 0);
    },
  );

  testWidgets(
    'split mode: the caret opens the terminal launch menu',
    (tester) async {
      var defaultCalls = 0;
      var menuCalls = 0;
      await tester.pumpWidget(
        _host(
          WorkspaceShellNewChatButton(
            tooltip: 'tooltip',
            newConversationLabel: '',
            newTerminalLabel: 'New terminal',
            // onNewConversation null → caret opens the target picker directly.
            onNewTerminal: (_) => menuCalls++,
            onNewTerminalDefault: () => defaultCalls++,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.arrow_drop_down_rounded));
      await tester.pump();

      expect(menuCalls, 1);
      expect(defaultCalls, 0);
    },
  );

  testWidgets(
    'legacy mode: without a default, the single "+" opens the launch menu',
    (tester) async {
      var menuCalls = 0;
      await tester.pumpWidget(
        _host(
          WorkspaceShellNewChatButton(
            tooltip: 'tooltip',
            newConversationLabel: '',
            newTerminalLabel: 'New terminal',
            onNewTerminal: (_) => menuCalls++,
          ),
        ),
      );

      // No caret in legacy mode.
      expect(find.byIcon(Icons.arrow_drop_down_rounded), findsNothing);

      await tester.tap(
        find.byKey(AppKeys.workspaceTabRowNewChatButton),
      );
      await tester.pump();

      expect(menuCalls, 1);
    },
  );
}
