import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/mobile_toolbar_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/pairing/mobile_toolbar/mobile_keyboard_toolbar.dart';
import 'package:teampilot/repositories/mobile_toolbar_repository.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

/// Short enough that one extra pump retires the cubit's usage-count debounce.
const _usageFlushDelay = Duration(milliseconds: 10);

void main() {
  late List<List<int>> sent;
  late MobileToolbarCubit cubit;

  setUp(() {
    sent = [];
    cubit = MobileToolbarCubit(
      repository: InMemoryMobileToolbarRepository(),
      sendInput: sent.add,
      readClipboard: () async => null,
      // Persistence timing belongs to the cubit's own tests. Leaving the
      // default one-second usage debounce armed here would trip
      // flutter_test's pending-timer invariant on every key tap, so keep it
      // short enough for [drainUsageFlush] to retire it.
      usageFlushDelay: _usageFlushDelay,
    );
  });

  tearDown(() => cubit.close());

  /// Advances past the cubit's usage debounce. A tap arms it, and flutter_test
  /// fails any test that ends with a timer still pending.
  Future<void> drainUsageFlush(WidgetTester tester) =>
      tester.pump(_usageFlushDelay * 2);

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox.expand()),
              BlocProvider.value(
                value: cubit,
                child: const MobileKeyboardToolbar(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders the default four groups and nothing beyond', (t) async {
    await pump(t);
    expect(find.byKey(AppKeys.mobileToolbar), findsOneWidget);
    for (final id in ['arrow_left', 'paste', 'esc', 'ctrl_c', 'ctrl_s']) {
      expect(find.byKey(AppKeys.mobileToolbarKey(id)), findsOneWidget,
          reason: '$id is in the first four groups');
    }
    expect(find.byKey(AppKeys.mobileToolbarKey('f1')), findsNothing);
    expect(find.byKey(AppKeys.mobileToolbarKey('home')), findsNothing);
  });

  testWidgets('tapping ^C sends 0x03', (t) async {
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileToolbarKey('ctrl_c')));
    await drainUsageFlush(t);
    expect(sent, [[0x03]]);
  });

  testWidgets('Ctrl then a key sends the control code once', (t) async {
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileToolbarKey('ctrl')));
    await t.pump();
    await t.tap(find.byKey(AppKeys.mobileToolbarKey('esc')));
    await drainUsageFlush(t);
    expect(sent, [[0x1b]], reason: 'Esc is already a control code');
    expect(cubit.state.ctrl, isFalse);
  });

  testWidgets('holding an arrow auto-repeats', (t) async {
    await pump(t);
    final gesture = await t.startGesture(
      t.getCenter(find.byKey(AppKeys.mobileToolbarKey('arrow_up'))),
    );
    await t.pump(kLongPressTimeout + const Duration(milliseconds: 10));
    await t.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await drainUsageFlush(t);
    expect(sent.length, greaterThanOrEqualTo(2));
    expect(sent.first, [0x1b, 0x5b, 0x41]);
  });

  testWidgets('keys still send after the keyboard is hidden', (t) async {
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileToolbarHideKeyboardButton));
    await t.pump();
    await t.tap(find.byKey(AppKeys.mobileToolbarKey('tab')));
    await drainUsageFlush(t);
    expect(sent, [[0x09]]);
  });
}
