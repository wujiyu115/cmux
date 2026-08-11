import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/image_upload_cubit.dart';
import 'package:teampilot/cubits/mobile_toolbar_cubit.dart';
import 'package:teampilot/cubits/voice_input_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/pairing/mobile_toolbar/mobile_composer_panel.dart';
import 'package:teampilot/repositories/mobile_toolbar_repository.dart';
import 'package:teampilot/repositories/voice_input_repository.dart';
import 'package:teampilot/services/stt/stt_provider.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/fake_stt_provider.dart';

void main() {
  late MobileToolbarCubit toolbar;
  late VoiceInputCubit voice;
  late ImageUploadCubit upload;
  late InMemoryVoiceInputRepository voiceRepository;
  late FakeSttProvider provider;
  late TextEditingController controller;
  late FocusNode focusNode;

  setUp(() {
    toolbar = MobileToolbarCubit(
      repository: InMemoryMobileToolbarRepository(),
      sendInput: (_) {},
      readClipboard: () async => null,
      usageFlushDelay: const Duration(milliseconds: 10),
    );
    voiceRepository = InMemoryVoiceInputRepository();
    provider = FakeSttProvider();
    voice = VoiceInputCubit(
      repository: voiceRepository,
      providerFactory: (_, _) => provider,
    );
    // The composer now requires an ImageUploadCubit in scope; this suite never
    // exercises uploads, so the callbacks are inert.
    upload = ImageUploadCubit(
      pickImage: () async => null,
      upload: ({required filename, required bytes, onProgress}) async => '',
    );
    controller = TextEditingController();
    focusNode = FocusNode();
  });

  tearDown(() async {
    await voice.close();
    await toolbar.close();
    await upload.close();
    controller.dispose();
    focusNode.dispose();
  });

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
                  BlocProvider.value(value: toolbar),
                  BlocProvider.value(value: voice),
                  BlocProvider.value(value: upload),
                ],
                child: MobileComposerPanel(
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

  testWidgets('shows the mic once a backend is available', (t) async {
    await voice.load();
    await pump(t);
    expect(find.byKey(AppKeys.mobileComposerMicButton), findsOneWidget);
  });

  testWidgets('keeps the mic when nothing can run, routed to settings', (
    t,
  ) async {
    // No on-device recognizer and no cloud keys. The action row is fixed, so the
    // button stays rather than reflowing the whole strip the moment a backend
    // appears; the tap goes to settings, its only useful outcome.
    final unavailable = VoiceInputCubit(
      repository: InMemoryVoiceInputRepository(),
      providerFactory: (_, _) => FakeSttProvider(availableValue: false),
    );
    addTearDown(unavailable.close);
    await unavailable.load();
    voice = unavailable;
    await pump(t);
    expect(find.byKey(AppKeys.mobileComposerMicButton), findsOneWidget);

    await t.tap(find.byKey(AppKeys.mobileComposerMicButton));
    await t.pumpAndSettle();
    expect(find.byKey(AppKeys.voiceSettingsPage), findsOneWidget);
    expect(provider.startCalls, 0);

    await t.tap(find.byTooltip('Back'));
    await t.pumpAndSettle();
  });

  testWidgets('tapping the mic starts a session', (t) async {
    await voice.load();
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerMicButton));
    await t.pump();
    await t.pump();
    expect(provider.startCalls, 1);
    expect(voice.state.status, VoiceInputStatus.listening);
  });

  testWidgets('shows the listening icon while a session is live', (t) async {
    await voice.load();
    await pump(t);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);

    await t.tap(find.byKey(AppKeys.mobileComposerMicButton));
    await t.pump();
    await t.pump();

    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsNothing);
  });

  testWidgets('tapping again stops the session', (t) async {
    await voice.load();
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerMicButton));
    await t.pump();
    await t.pump();
    await t.tap(find.byKey(AppKeys.mobileComposerMicButton));
    await t.pump();
    await t.pump();
    expect(provider.stopCalls, 1);
    expect(voice.state.status, VoiceInputStatus.idle);
  });

  testWidgets('shows the provider badge', (t) async {
    await voiceRepository.savePrefs(
      const VoiceInputPrefs(provider: SttProviderType.volcengine, localeId: ''),
    );
    await voiceRepository.saveCredential(VoiceCredentialField.volcAppId, 'a');
    await voiceRepository.saveCredential(
      VoiceCredentialField.volcAccessToken,
      'b',
    );
    await voice.load();
    await pump(t);
    expect(find.text('DOU'), findsOneWidget);
  });

  testWidgets('closing the composer stops a live session', (t) async {
    // One of the four paths that must not leave the microphone hot.
    await voice.load();
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerMicButton));
    await t.pump();
    await t.pump();

    await t.tap(find.byKey(AppKeys.mobileComposerCloseButton));
    await t.pump();

    expect(provider.stopCalls, 1);
  });

  testWidgets('surfaces a denied microphone as a snack bar', (t) async {
    await voice.load();
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerMicButton));
    await t.pump();
    await t.pump();

    provider.fail(const VoicePermissionDeniedException());
    await t.pump();
    await t.pump();

    expect(
      find.text('Microphone access denied. Enable it in system settings.'),
      findsOneWidget,
    );
  });

  testWidgets('surfaces any other failure as a snack bar', (t) async {
    await voice.load();
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerMicButton));
    await t.pump();
    await t.pump();

    provider.fail(const SttException('socket died'));
    await t.pump();
    await t.pump();

    expect(find.text('Voice input failed'), findsOneWidget);
  });

  testWidgets('long-pressing the mic opens voice settings', (t) async {
    await voice.load();
    await pump(t);
    await t.longPress(find.byKey(AppKeys.mobileComposerMicButton));
    await t.pumpAndSettle();
    expect(find.byKey(AppKeys.voiceSettingsPage), findsOneWidget);

    // Pop back to the composer so the tree ends where the other tests leave it;
    // disposing the shared focus node under a lingering route trips the focus
    // manager during tearDown.
    await t.tap(find.byTooltip('Back'));
    await t.pumpAndSettle();
  });

  testWidgets('tapping an unconfigured mic opens voice settings', (t) async {
    // The tap's only useful outcome is configuration, so go there instead of
    // reporting a failure the user cannot act on from here.
    await voiceRepository.savePrefs(
      const VoiceInputPrefs(provider: SttProviderType.aliyun, localeId: ''),
    );
    await voice.load();
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerMicButton));
    await t.pumpAndSettle();
    expect(find.byKey(AppKeys.voiceSettingsPage), findsOneWidget);
    expect(provider.startCalls, 0);

    await t.tap(find.byTooltip('Back'));
    await t.pumpAndSettle();
  });

  testWidgets('the mic announces a label that tracks its state', (t) async {
    // The mic cannot borrow TpIconButton's tooltip (its long-press recognizer
    // would swallow long-press-to-settings), so the label is supplied by a
    // Semantics node directly — assert it is present and flips with state.
    Semantics micSemantics() => t.widget<Semantics>(
      find
          .descendant(
            of: find.byKey(AppKeys.mobileComposerMicButton),
            matching: find.byType(Semantics),
          )
          .first,
    );

    await voice.load();
    await pump(t);

    expect(micSemantics().properties.button, true);
    expect(micSemantics().properties.label, 'Start dictation');

    await t.tap(find.byKey(AppKeys.mobileComposerMicButton));
    await t.pump();
    await t.pump();

    expect(voice.state.status, VoiceInputStatus.listening);
    expect(micSemantics().properties.label, 'Stop dictation');
  });
}
