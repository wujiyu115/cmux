import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/pairing_client_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/pairing/mobile_chrome.dart';
import 'package:teampilot/pages/pairing/paired_hosts_page.dart';
import 'package:teampilot/repositories/pairing_settings_repository.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

/// The tablet nav is the same for iPad and Android large screens: the split is a
/// *size* question, never a `Platform` one, so these assertions hold for both.
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  group('MobileNavRail', () {
    testWidgets('offers both destinations and reports the tapped one', (
      tester,
    ) async {
      final taps = <MobileTab>[];
      await pumpAt(
        tester,
        const Size(1024, 768),
        MobileNavRail(current: MobileTab.activity, onSelected: taps.add),
      );

      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      await tester.tap(find.byKey(AppKeys.mobileSettingsButton));
      expect(taps, [MobileTab.settings]);
    });
  });

  group('PairedHostsPage nav', () {
    Future<void> pumpHosts(WidgetTester tester, Size size) async {
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
      );
      addTearDown(cubit.close);
      await pumpAt(
        tester,
        size,
        BlocProvider<PairingClientCubit>.value(
          value: cubit,
          child: PairedHostsPage(onScan: () {}),
        ),
      );
    }

    testWidgets('a tablet gets the leading rail and no bottom bar', (
      tester,
    ) async {
      await pumpHosts(tester, const Size(1024, 768));

      expect(find.byKey(AppKeys.mobileNavRail), findsOneWidget);
      expect(find.byType(MobileBottomNav), findsNothing);
      // The rail is on the leading edge: the feed starts to its right.
      expect(tester.getTopLeft(find.byKey(AppKeys.mobileNavRail)).dx, 0);
      expect(
        tester.getSize(find.byKey(AppKeys.mobileNavRail)).width,
        MobileNavRail.width,
      );
    });

    testWidgets('a phone keeps the bottom bar', (tester) async {
      await pumpHosts(tester, const Size(393, 852));

      expect(find.byType(MobileBottomNav), findsOneWidget);
      expect(find.byKey(AppKeys.mobileNavRail), findsNothing);
    });
  });
}
