import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/bark_push_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/bark_push_schedule.dart';
import 'package:teampilot/models/bark_push_settings.dart';
import 'package:teampilot/pages/config/push_channel_section.dart';
import 'package:teampilot/repositories/bark_push_repository.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/services/notification/bark_push_sender.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

void main() {
  late InMemoryBarkPushRepository repository;
  late List<String> pushes;
  late BarkPushCubit cubit;

  /// Body the fake Bark server answers with, so a test can make the push fail.
  var responseBody = '{"code":200}';

  BarkPushCubit build({String deviceKey = ''}) {
    repository = InMemoryBarkPushRepository(deviceKey: deviceKey);
    return BarkPushCubit(
      repository: repository,
      sender: BarkPushSender(
        client: MockClient((request) async {
          pushes.add(request.body);
          return http.Response(responseBody, 200);
        }),
      ),
      testTitle: () => 'TeamPilot',
      testBody: () => 'Push channel works.',
    );
  }

  setUp(() {
    pushes = [];
    responseBody = '{"code":200}';
  });

  tearDown(() => cubit.close());

  Future<void> pump(WidgetTester tester) async {
    // Tall viewport: the section is a scrolling settings column and the test
    // button must be hit-testable without scrolling in every test.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final theme = ThemeData.light();
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
            body: BlocProvider<BarkPushCubit>.value(
              value: cubit,
              child: const SingleChildScrollView(child: PushChannelSection()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('seeds the fields from the stored settings and key', (
    tester,
  ) async {
    cubit = build(deviceKey: 'stored-key');
    await cubit.load();
    await pump(tester);

    expect(
      tester
          .widget<TextField>(find.byKey(AppKeys.barkPushServerField))
          .controller!
          .text,
      BarkPushSettings.defaultServerUrl,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(AppKeys.barkPushDeviceKeyField))
          .controller!
          .text,
      'stored-key',
    );
  });

  testWidgets('test button is disabled until a device key is entered', (
    tester,
  ) async {
    cubit = build();
    await cubit.load();
    await pump(tester);

    expect(
      tester.widget<TpButton>(find.byKey(AppKeys.barkPushTestButton)).onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(AppKeys.barkPushDeviceKeyField),
      'typed-key',
    );
    await tester.pump();

    expect(
      tester.widget<TpButton>(find.byKey(AppKeys.barkPushTestButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('pressing test sends with the key just typed, before the '
      'debounce would have saved it', (tester) async {
    cubit = build();
    await cubit.load();
    await pump(tester);

    await tester.enterText(
      find.byKey(AppKeys.barkPushDeviceKeyField),
      'typed-key',
    );
    await tester.pump();
    await tester.tap(find.byKey(AppKeys.barkPushTestButton));
    await tester.pumpAndSettle();

    expect(pushes.single, contains('"device_key":"typed-key"'));
    expect(find.text('Test push delivered.'), findsOneWidget);
    // The press also persists, so the key survives leaving the page.
    expect(await repository.loadDeviceKey(), 'typed-key');
  });

  testWidgets('a refused push shows the server\'s own words', (tester) async {
    responseBody = '{"code":400,"message":"failed to get device token"}';
    cubit = build(deviceKey: 'stale');
    await cubit.load();
    await pump(tester);

    await tester.tap(find.byKey(AppKeys.barkPushTestButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('failed to get device token'), findsOneWidget);
  });

  testWidgets('changing the mode persists it', (tester) async {
    cubit = build(deviceKey: 'k');
    await cubit.load();
    await pump(tester);

    await tester.tap(find.byKey(AppKeys.barkPushModeDropdown));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Always').last);
    await tester.pumpAndSettle();

    expect((await repository.loadSettings()).mode, BarkPushMode.always);
  });

  testWidgets('toggling "only phone-typed turns" persists it', (tester) async {
    cubit = build(deviceKey: 'k');
    await cubit.load();
    await pump(tester);

    // Default is on: only phone-originated turns get pushed.
    expect((await repository.loadSettings()).mobileInputOnly, isTrue);

    await tester.tap(find.byKey(AppKeys.barkPushMobileInputOnlySwitch));
    await tester.pumpAndSettle();

    expect((await repository.loadSettings()).mobileInputOnly, isFalse);
  });

  group('push schedule', () {
    /// Wide enough for [TpSegmentedPicker]'s pill mode (its compact-select
    /// fallback sits below 840 logical px).
    Future<void> pumpWide(WidgetTester tester) async {
      await pump(tester);
      tester.view.physicalSize = const Size(1400, 1600);
      await tester.pumpAndSettle();
    }

    testWidgets('mode, days and window persist', (tester) async {
      cubit = build(deviceKey: 'k');
      await cubit.load();
      await pumpWide(tester);

      // Off by default: the day chips and times are hidden.
      expect((await repository.loadSettings()).schedule.isActive, isFalse);
      expect(
        find.byKey(AppKeys.barkPushScheduleDay(DateTime.monday)),
        findsNothing,
      );

      await tester.tap(find.text('Allowlist'));
      await tester.pumpAndSettle();
      final allow = (await repository.loadSettings()).schedule;
      expect(allow.mode, BarkPushScheduleMode.allow);
      expect(
        find.byKey(AppKeys.barkPushScheduleDay(DateTime.monday)),
        findsOneWidget,
      );

      // Every day starts selected; tapping one deselects it.
      await tester.tap(find.byKey(AppKeys.barkPushScheduleDay(DateTime.friday)));
      await tester.pumpAndSettle();
      expect(
        (await repository.loadSettings()).schedule.days,
        isNot(contains(DateTime.friday)),
      );

      await tester.tap(find.text('Blocklist'));
      await tester.pumpAndSettle();
      expect(
        (await repository.loadSettings()).schedule.mode,
        BarkPushScheduleMode.block,
      );
    });

    testWidgets('the last selected day cannot be deselected', (tester) async {
      cubit = build(deviceKey: 'k');
      await cubit.load();
      await cubit.setSchedule(
        const BarkPushSchedule(
          mode: BarkPushScheduleMode.allow,
          days: {DateTime.monday},
        ),
      );
      await pumpWide(tester);

      await tester.tap(find.byKey(AppKeys.barkPushScheduleDay(DateTime.monday)));
      await tester.pumpAndSettle();

      // An empty set would read as "every day" — the opposite of the intent.
      expect(
        (await repository.loadSettings()).schedule.days,
        {DateTime.monday},
      );
    });

    testWidgets('the time buttons open the picker', (tester) async {
      cubit = build(deviceKey: 'k');
      await cubit.load();
      await cubit.setSchedule(
        const BarkPushSchedule(mode: BarkPushScheduleMode.allow),
      );
      await pumpWide(tester);

      await tester.tap(find.byKey(AppKeys.barkPushScheduleStart));
      await tester.pumpAndSettle();
      expect(find.text('Start time'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Start time'), findsNothing);
    });
  });
}
