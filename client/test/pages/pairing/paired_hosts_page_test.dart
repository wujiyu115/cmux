import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/pairing_client_cubit.dart';
import 'package:teampilot/cubits/voice_input_cubit.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/repositories/pairing_settings_repository.dart';
import 'package:teampilot/repositories/voice_input_repository.dart';
import 'package:teampilot/pages/pairing/paired_hosts_page.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/fake_stt_provider.dart';

class _TestCubit extends PairingClientCubit {
  _TestCubit(PairingSettingsRepository settings) : super(settings: settings);
  void set(PairingClientState s) => emit(s);
}

const _desktop = PairedDesktop(
  id: 'd1',
  name: 'Studio Desktop',
  wsUrls: ['ws://192.168.1.5:5555/pair/ws'],
  hostPublicKeyB64: 'pk',
  deviceToken: 't',
);

void main() {
  late _TestCubit cubit;
  late InMemoryPairingSettingsRepository settings;

  setUp(() {
    settings = InMemoryPairingSettingsRepository();
    cubit = _TestCubit(settings);
  });
  tearDown(() => cubit.close());

  Future<void> pump(WidgetTester tester, {required VoidCallback onScan}) async {
    await tester.pumpWidget(
      // Removing a host raises an undo toast, which needs the app's toast
      // overlay host to render.
      TpToastWrapper(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BlocProvider<PairingClientCubit>.value(
            value: cubit,
            child: PairedHostsPage(onScan: onScan),
          ),
        ),
      ),
    );
  }

  /// Toasts hold an auto-close timer; leaving one running fails the test with a
  /// pending-timer error.
  Future<void> clearToasts(WidgetTester tester) async {
    AppToast.dismiss();
    await tester.pumpAndSettle();
  }

  testWidgets('the pair row and the floating add both open the scanner', (
    tester,
  ) async {
    var scans = 0;
    await pump(tester, onScan: () => scans++);

    expect(find.byKey(AppKeys.pairedHostsPage), findsOneWidget);
    expect(find.text('No paired desktops yet.'), findsOneWidget);
    expect(find.text('Pair a desktop'), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.pairingScanCtaButton));
    expect(scans, 1);

    // The thumb-reachable FAB is the same action, not a second concept.
    await tester.tap(find.byKey(AppKeys.mobileAddDesktopButton));
    expect(scans, 2);

    // Same row, same place, once desktops exist.
    cubit.set(const PairingClientState(pairedDesktops: [_desktop]));
    await tester.pump();
    expect(find.text('Pair a desktop'), findsOneWidget);
    await tester.tap(find.byKey(AppKeys.pairingScanCtaButton));
    expect(scans, 3);
  });

  testWidgets('paired desktops render as rows', (tester) async {
    cubit.set(const PairingClientState(pairedDesktops: [_desktop]));
    await pump(tester, onScan: () {});

    expect(find.byKey(const ValueKey('paired-desktop-d1')), findsOneWidget);
    expect(find.text('Studio Desktop'), findsOneWidget);
    expect(find.text('ws://192.168.1.5:5555/pair/ws'), findsOneWidget);
    expect(find.text('No paired desktops yet.'), findsNothing);
  });

  testWidgets('the last-connected line only renders once stamped', (
    tester,
  ) async {
    cubit.set(const PairingClientState(pairedDesktops: [_desktop]));
    await pump(tester, onScan: () {});
    expect(find.textContaining('Last connected'), findsNothing);

    cubit.set(
      PairingClientState(
        pairedDesktops: [_desktop.copyWith(lastConnectedAt: DateTime.now())],
      ),
    );
    await tester.pump();
    expect(find.textContaining('Last connected'), findsOneWidget);
  });

  testWidgets('the local IP strip appears only when an address resolved', (
    tester,
  ) async {
    cubit.set(const PairingClientState(pairedDesktops: [_desktop]));
    await pump(tester, onScan: () {});
    expect(find.byKey(AppKeys.pairingNetworkStrip), findsNothing);

    cubit.set(
      const PairingClientState(
        pairedDesktops: [_desktop],
        localIp: '192.168.1.37',
      ),
    );
    await tester.pump();
    expect(find.byKey(AppKeys.pairingNetworkStrip), findsOneWidget);
    expect(find.text('192.168.1.37'), findsOneWidget);
  });

  testWidgets('the remove button drops the desktop back to the empty state', (
    tester,
  ) async {
    await settings.savePairedDesktops(const [_desktop]);
    cubit.set(const PairingClientState(pairedDesktops: [_desktop]));
    await pump(tester, onScan: () {});

    await tester.tap(find.byTooltip('Remove'));
    await tester.pump();
    await clearToasts(tester);

    expect(find.byKey(const ValueKey('paired-desktop-d1')), findsNothing);
    expect(find.text('No paired desktops yet.'), findsOneWidget);
    expect(await settings.loadPairedDesktops(), isEmpty);
  });

  testWidgets('removing offers an undo that restores the desktop', (
    tester,
  ) async {
    await settings.savePairedDesktops(const [_desktop]);
    cubit.set(const PairingClientState(pairedDesktops: [_desktop]));
    await pump(tester, onScan: () {});

    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(await settings.loadPairedDesktops(), isEmpty);

    expect(find.text('Removed Studio Desktop'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    await clearToasts(tester);

    expect(cubit.state.pairedDesktops.single.id, 'd1');
    expect((await settings.loadPairedDesktops()).single.id, 'd1');
  });

  testWidgets('the bottom bar swaps the feed for settings and back', (
    tester,
  ) async {
    // Pinned to a phone: at the widget-test default 800×600 the page is past the
    // 600pt tablet breakpoint and renders the rail instead, which the
    // mobile_nav_rail_test covers.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);
    final layout = LayoutCubit();
    addTearDown(layout.close);
    final voice = VoiceInputCubit(
      repository: InMemoryVoiceInputRepository(),
      providerFactory: (_, _) => FakeSttProvider(),
    );
    addTearDown(voice.close);
    await voice.load();

    final theme = ThemeData(useMaterial3: true);
    await tester.pumpWidget(
      TpToastWrapper(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: theme,
          home: MultiBlocProvider(
            providers: [
              BlocProvider<PairingClientCubit>.value(value: cubit),
              BlocProvider<LayoutCubit>.value(value: layout),
              BlocProvider<VoiceInputCubit>.value(value: voice),
            ],
            child: TpTheme(
              data: TpThemeData.fromColorScheme(
                theme.colorScheme,
                scale: 1.0,
                controlScale: AppTypographyScale.standard.multiplier,
              ),
              child: PairedHostsPage(onScan: () {}),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(AppKeys.mobileSettingsPage), findsNothing);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.mobileSettingsPage), findsOneWidget);
    expect(find.byKey(AppKeys.languageSystemButton), findsOneWidget);

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.byKey(AppKeys.mobileSettingsPage), findsNothing);
    expect(find.text('Desktops'), findsOneWidget);
  });
}
