import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/pairing_host_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/config/pairing_config_section.dart';
import 'package:teampilot/repositories/pairing_key_store.dart';
import 'package:teampilot/repositories/pairing_settings_repository.dart';
import 'package:teampilot/services/pairing/device_registry.dart';
import 'package:teampilot/services/pairing/lan_pairing_server.dart';
import 'package:teampilot/services/pairing/pairing_crypto.dart';
import 'package:teampilot/services/pairing/pairing_offer.dart';
import 'package:teampilot/services/pairing/session_catalog.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/pairing_upload_doubles.dart';

/// No socket: this is a layout/wiring test for "此电脑的地址".
class _FakeServer extends LanPairingServer {
  _FakeServer({super.advertisedAddress})
    : super(
        hostStaticKey: PairingKeyPair.generate(),
        registry: DeviceRegistry(InMemoryPairingKeyStore()),
        catalog: SessionCatalog(),
        hostName: 'Studio',
        uploadOpener: noopUploadOpener,
      );

  @override
  Future<void> ensureStarted() async {}

  @override
  Future<void> dispose() async {}

  @override
  bool get isRunning => true;

  @override
  int get port => 4321;

  @override
  Future<List<String>> lanWsUrls() async => [
    'ws://${advertisedAddress ?? '0.0.0.0'}:4321/pair/ws',
  ];

  @override
  Future<PairingOffer> createOffer({
    Duration ttl = PairingOfferWindow.defaultTtl,
  }) async => PairingOffer(
    version: 1,
    wsUrls: await lanWsUrls(),
    token: 'code',
    hostPublicKeyB64: 'pk',
    expiresAtMs: 0,
  );
}

void main() {
  late InMemoryPairingSettingsRepository settings;
  late PairingHostCubit cubit;
  late int listCalls;

  const interfaces = [
    PairingInterfaceAddress(name: 'peer-tank-wg0-4', ip: '10.253.0.5'),
    PairingInterfaceAddress(name: 'Ethernet', ip: '30.210.200.83'),
  ];

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme = ThemeData.dark(useMaterial3: true);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme,
        home: TpTheme(
          data: TpThemeData.fromColorScheme(
            theme.colorScheme,
            scale: 1.0,
            controlScale: AppTypographyScale.standard.multiplier,
          ),
          child: Scaffold(
            body: BlocProvider<PairingHostCubit>.value(
              value: cubit,
              child: const PairingConfigWorkspace(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    settings = InMemoryPairingSettingsRepository(hostEnabled: true);
    listCalls = 0;
    cubit = PairingHostCubit(
      settings: settings,
      registry: DeviceRegistry(InMemoryPairingKeyStore()),
      serverFactory: (advertisedAddress) =>
          _FakeServer(advertisedAddress: advertisedAddress),
      interfaceLister: () async {
        listCalls++;
        return interfaces;
      },
    );
    addTearDown(cubit.close);
  });

  testWidgets('lists this machine addresses as ip (interface)', (tester) async {
    await tester.runAsync(cubit.init);
    await pump(tester);

    expect(find.text('This computer’s address'), findsOneWidget);
    expect(find.byKey(AppKeys.pairingLocalAddressSelect), findsOneWidget);
    // The picker seeds from the running server, before any choice.
    expect(find.text('All interfaces'), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.pairingLocalAddressSelect));
    await tester.pumpAndSettle();
    expect(find.text('30.210.200.83 (Ethernet)'), findsOneWidget);

    await tester.tap(find.text('30.210.200.83 (Ethernet)').last);
    await tester.pumpAndSettle();

    expect(cubit.state.advertisedAddress, '30.210.200.83');
    expect(await tester.runAsync(settings.loadPairingHostAddress),
        '30.210.200.83');
    // One URL in the offer ⇒ the phone has nothing to probe.
    expect(cubit.state.offer!.wsUrls, ['ws://30.210.200.83:4321/pair/ws']);
  });

  testWidgets('a custom address can be typed in', (tester) async {
    await tester.runAsync(cubit.init);
    await pump(tester);

    await tester.tap(find.byKey(AppKeys.pairingLocalAddressSelect));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add custom address…').last);
    await tester.pumpAndSettle();

    // The dialog refuses a bare scheme / empty input.
    await tester.enterText(find.byType(TpInput), 'http://');
    await tester.tap(find.byKey(AppKeys.pairingLocalAddressCustomSave));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid IP address or hostname.'), findsOneWidget);
    expect(cubit.state.advertisedAddress, isNull);

    await tester.enterText(find.byType(TpInput), 'studio.example.com');
    await tester.tap(find.byKey(AppKeys.pairingLocalAddressCustomSave));
    await tester.pumpAndSettle();

    expect(cubit.state.advertisedAddress, 'studio.example.com');
    expect(find.text('studio.example.com'), findsOneWidget);
  });

  testWidgets('refresh re-reads the interface list', (tester) async {
    await tester.runAsync(cubit.init);
    await pump(tester);
    final before = listCalls;

    await tester.tap(find.byKey(AppKeys.pairingLocalAddressRefresh));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();

    expect(listCalls, greaterThan(before));
  });
}