import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/mobile_toolbar_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/toolbar_key.dart';
import 'package:teampilot/pages/pairing/mobile_toolbar/mobile_toolbar_customize_page.dart';
import 'package:teampilot/repositories/mobile_toolbar_repository.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

/// Short enough that one extra pump retires the cubit's usage-count debounce.
const _usageFlushDelay = Duration(milliseconds: 10);

void main() {
  late InMemoryMobileToolbarRepository repo;
  late MobileToolbarCubit cubit;

  setUp(() async {
    repo = InMemoryMobileToolbarRepository();
    cubit = MobileToolbarCubit(
      repository: repo,
      sendInput: (_) {},
      readClipboard: () async => null,
      usageFlushDelay: _usageFlushDelay,
    );
    await cubit.load();
  });

  tearDown(() => cubit.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider.value(
          value: cubit,
          child: const MobileToolbarCustomizePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists every group with its localized name', (t) async {
    await pump(t);
    expect(find.byKey(AppKeys.mobileToolbarCustomizePage), findsOneWidget);
    expect(find.text('Arrows'), findsOneWidget);
    expect(find.text('Visible groups: 4'), findsOneWidget);
    // The list is scrollable, so only the leading tiles are laid out; scroll to
    // each remaining id rather than asserting all sixteen are on screen.
    for (final id in defaultToolbarGroupIds) {
      final tile = find.byKey(AppKeys.mobileToolbarGroupTile(id));
      await t.scrollUntilVisible(tile, 120);
      expect(tile, findsOneWidget);
    }
  });

  testWidgets('increasing the visible count persists', (t) async {
    await pump(t);
    await t.tap(find.byIcon(Icons.add));
    await t.pumpAndSettle();
    expect(cubit.state.visibleGroupCount, 5);
    expect(repo.lastSaved!.visibleGroupCount, 5);
    expect(find.text('Visible groups: 5'), findsOneWidget);
  });

  testWidgets('decreasing stops at one instead of underflowing', (t) async {
    await pump(t);
    for (var i = 0; i < 5; i++) {
      await t.tap(find.byIcon(Icons.remove));
      await t.pumpAndSettle();
    }
    expect(cubit.state.visibleGroupCount, 1);
  });

  testWidgets('reset restores the built-in order', (t) async {
    await cubit.reorderGroups(4, 0);
    expect(cubit.state.groupOrder.first, isNot('arrows'));
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileToolbarResetButton));
    await t.pumpAndSettle();
    expect(cubit.state.groupOrder, defaultToolbarGroupIds);
    expect(repo.lastSaved!.groupOrder, defaultToolbarGroupIds);
  });

  testWidgets('most-used section appears once a key has been pressed', (
    t,
  ) async {
    await pump(t);
    expect(find.text('Most used'), findsNothing);
    await cubit.tapKey(toolbarKeyById('esc')!);
    await t.pump(_usageFlushDelay * 2);
    expect(find.text('Most used'), findsOneWidget);
    expect(find.text('Esc'), findsWidgets);
  });
}
