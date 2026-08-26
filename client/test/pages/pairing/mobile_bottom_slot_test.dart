import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/media_upload_cubit.dart';
import 'package:teampilot/cubits/mobile_toolbar_cubit.dart';
import 'package:teampilot/cubits/voice_input_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/toolbar_key.dart';
import 'package:teampilot/pages/pairing/mobile_toolbar/mobile_bottom_slot.dart';
import 'package:teampilot/pages/pairing/mobile_toolbar/mobile_composer_panel.dart';
import 'package:teampilot/pages/pairing/mobile_toolbar/mobile_keyboard_toolbar.dart';
import 'package:teampilot/repositories/mobile_toolbar_repository.dart';
import 'package:teampilot/repositories/voice_input_repository.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/fake_stt_provider.dart';

/// Short enough that one extra pump retires the cubit's usage-count debounce.
const _usageFlushDelay = Duration(milliseconds: 10);

void main() {
  late List<List<int>> sent;
  late MobileToolbarCubit cubit;
  late VoiceInputCubit voice;
  late MediaUploadCubit upload;
  late TextEditingController controller;
  late FocusNode focusNode;

  setUp(() {
    sent = [];
    cubit = MobileToolbarCubit(
      repository: InMemoryMobileToolbarRepository(),
      sendInput: sent.add,
      readClipboard: () async => null,
      // A key tap arms the usage debounce; flutter_test fails any test that
      // ends with a pending timer, so keep it short enough for
      // [drainUsageFlush] to retire it.
      usageFlushDelay: _usageFlushDelay,
    );
    // The composer now requires a VoiceInputCubit in scope. Left unloaded so
    // no backend is available and the mic button stays hidden.
    voice = VoiceInputCubit(
      repository: InMemoryVoiceInputRepository(),
      providerFactory: (_, _) => FakeSttProvider(),
    );
    // The composer now requires an MediaUploadCubit in scope; this suite never
    // exercises uploads, so the callbacks are inert.
    upload = MediaUploadCubit(
      pickMedia: () async => null,
      upload: ({required filename, required source, onProgress}) async => '',
    );
    // The slot forwards these to the composer; the mirror page owns them, so
    // the test mirrors that ownership by creating and disposing them here.
    controller = TextEditingController();
    focusNode = FocusNode();
  });

  tearDown(() async {
    await cubit.close();
    await voice.close();
    await upload.close();
    controller.dispose();
    focusNode.dispose();
  });

  /// Advances past the cubit's usage debounce.
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
              MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: cubit),
                  BlocProvider.value(value: voice),
                  BlocProvider.value(value: upload),
                ],
                child: MobileBottomSlot(
                  controller: controller,
                  focusNode: focusNode,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('starts on the key bar', (t) async {
    await pump(t);
    expect(find.byType(MobileKeyboardToolbar), findsOneWidget);
    expect(find.byType(MobileComposerPanel), findsNothing);
  });

  testWidgets('toggleComposer swaps the key bar for the composer', (t) async {
    await pump(t);
    cubit.toggleComposer();
    // Two frames: the emit is delivered on the first pump's async gap (which
    // marks the BlocBuilder dirty) and rebuilt on the second.
    await t.pump();
    await t.pump();
    expect(find.byType(MobileComposerPanel), findsOneWidget);
    expect(find.byType(MobileKeyboardToolbar), findsNothing);
  });

  testWidgets('a usage-bumping emit does not unmount the composer', (t) async {
    await pump(t);
    cubit.toggleComposer();
    // Two frames so the composer is actually mounted before we type into it
    // (the emit is delivered on the first pump, rebuilt on the second).
    await t.pump();
    await t.pump();
    await t.enterText(find.byKey(AppKeys.mobileComposerField), 'ls -la');
    await t.pump();

    // Tapping a key bumps the usage counter and re-emits with no value
    // equality. What is pinned here is the user-facing contract: the composer
    // stays mounted with its text. It does NOT prove the slot's `buildWhen`
    // fires — probing showed the composer's State survives an extra rebuild
    // anyway (same widget type, caller-owned controller), so `buildWhen` is a
    // rebuild-count and on-device IME optimization, not what saves the draft.
    await cubit.tapKey(toolbarKeyById('esc')!);
    await drainUsageFlush(t);

    expect(find.byType(MobileComposerPanel), findsOneWidget);
    // Read the live field, not the controller the test itself owns: nothing on
    // the usage path could clear the latter, so it would pass even unmounted.
    expect(
      t.widget<TextField>(find.byKey(AppKeys.mobileComposerField)).controller,
      controller,
    );
    expect(find.text('ls -la'), findsOneWidget);
  });

  testWidgets('round trip through the real bar and composer buttons', (
    t,
  ) async {
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileToolbarComposerButton));
    await t.pump();
    expect(find.byType(MobileComposerPanel), findsOneWidget);

    await t.tap(find.byKey(AppKeys.mobileComposerCloseButton));
    await t.pump();
    expect(find.byType(MobileKeyboardToolbar), findsOneWidget);
    expect(find.byType(MobileComposerPanel), findsNothing);
  });
}
