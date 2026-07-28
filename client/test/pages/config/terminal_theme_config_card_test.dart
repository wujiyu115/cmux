import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/config/terminal_theme/terminal_theme_config_card.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  Future<LayoutCubit> pumpCard(WidgetTester tester) async {
    final cubit = LayoutCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider.value(
          value: cubit,
          child: const Scaffold(
            body: SingleChildScrollView(child: TerminalThemeConfigCard()),
          ),
        ),
      ),
    );
    await tester.pump();
    return cubit;
  }

  testWidgets('picking a theme writes its id via the cubit', (tester) async {
    final cubit = await pumpCard(tester);
    expect(cubit.state.preferences.terminalThemeMode, 'adaptive');

    await tester.ensureVisible(find.text('Dracula'));
    await tester.tap(find.text('Dracula'));
    await tester.pump();

    expect(cubit.state.preferences.terminalThemeMode, 'dracula');
  });

  testWidgets('custom colours toggle enables the slot editor', (tester) async {
    final cubit = await pumpCard(tester);
    expect(cubit.state.preferences.useCustomTerminalColors, isFalse);

    final switchFinder = find.byType(Switch);
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pump();

    expect(cubit.state.preferences.useCustomTerminalColors, isTrue);

    // Slot fields become editable once the toggle is on.
    final field = find.byType(TextField).first;
    final widget = tester.widget<TextField>(field);
    expect(widget.enabled, isTrue);
  });

  testWidgets('invalid hex shows error and does not write; valid hex writes', (
    tester,
  ) async {
    final cubit = await pumpCard(tester);

    final switchFinder = find.byType(Switch);
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pump();
    expect(cubit.state.preferences.useCustomTerminalColors, isTrue);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // First slot field is `background`.
    final field = find.byType(TextField).first;
    await tester.ensureVisible(field);

    await tester.enterText(field, 'zzz');
    await tester.pump();
    expect(find.text(l10n.terminalColorInvalidHex), findsOneWidget);
    expect(
      cubit.state.preferences.terminalColorOverrides.containsKey('background'),
      isFalse,
    );

    await tester.enterText(field, '#010203');
    await tester.pump();
    expect(find.text(l10n.terminalColorInvalidHex), findsNothing);
    expect(
      cubit.state.preferences.terminalColorOverrides['background'],
      0xFF010203,
    );
  });
}
