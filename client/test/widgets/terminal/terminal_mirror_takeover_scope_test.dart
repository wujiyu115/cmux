import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/widgets/terminal/terminal_mirror_takeover_scope.dart';

import '../../support/fake_terminal_session.dart';

Widget _wrap(Widget child) {
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
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('yields the pane while a phone mirrors it, then restores',
      (tester) async {
    final session = FakeTerminalSession();
    addTearDown(session.dispose);
    final key = GlobalKey<TerminalViewState>();
    final readOnlyLog = <bool>[];

    await tester.pumpWidget(
      _wrap(
        TerminalMirrorTakeoverScope(
          session: session,
          terminalViewKey: key,
          builder: (readOnly) {
            readOnlyLog.add(readOnly);
            return TerminalView(session.engine, key: key, readOnly: readOnly);
          },
        ),
      ),
    );
    await tester.pump();

    // Idle: no banner, pane is writable.
    expect(find.text('A phone is using this terminal'), findsNothing);
    expect(readOnlyLog.last, isFalse);

    // Phone attaches → banner covers the pane, builder rebuilds read-only.
    session.attachMirror();
    session.onTerminalPtyResize(84, 67);
    await tester.pump();

    expect(find.text('A phone is using this terminal'), findsOneWidget);
    expect(find.textContaining('84×67'), findsOneWidget);
    expect(readOnlyLog.last, isTrue);

    // Phone disconnects → banner gone, pane writable again.
    session.detachMirror();
    await tester.pump();

    expect(find.text('A phone is using this terminal'), findsNothing);
    expect(readOnlyLog.last, isFalse);
  });
}
