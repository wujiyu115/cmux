import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/media_upload_cubit.dart';
import 'package:teampilot/cubits/mobile_toolbar_cubit.dart';
import 'package:teampilot/cubits/voice_input_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/pairing/mobile_toolbar/mobile_composer_panel.dart';
import 'package:teampilot/repositories/mobile_toolbar_repository.dart';
import 'package:teampilot/repositories/voice_input_repository.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/fake_stt_provider.dart';

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
      usageFlushDelay: const Duration(milliseconds: 10),
    );
    cubit.setMode(MobileInputMode.composer);
    // The composer now requires a VoiceInputCubit in scope. Left unloaded so
    // no backend is available and the mic button stays hidden.
    voice = VoiceInputCubit(
      repository: InMemoryVoiceInputRepository(),
      providerFactory: (_, _) => FakeSttProvider(),
    );
    // The composer now requires an MediaUploadCubit in scope; this suite never
    // exercises uploads, so the callbacks are inert.
    upload = MediaUploadCubit(
      pickMedia: () async => const [],
      upload: ({required filename, required source, onProgress}) async => '',
    );
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

  testWidgets('renders the field and its five controls', (t) async {
    await pump(t);
    expect(find.byKey(AppKeys.mobileComposerPanel), findsOneWidget);
    expect(find.text('Type a command'), findsOneWidget);
    for (final key in [
      AppKeys.mobileComposerField,
      AppKeys.mobileComposerSendButton,
      AppKeys.mobileComposerCloseButton,
      AppKeys.mobileComposerSubmitToggle,
      // The attach (+) button is the fifth control, added with image upload.
      AppKeys.mobileComposerAttachButton,
    ]) {
      expect(find.byKey(key), findsOneWidget);
    }
  });

  testWidgets('takes focus when it mounts so the keyboard opens', (t) async {
    await pump(t);
    expect(focusNode.hasFocus, isTrue);
  });

  testWidgets('send appends CR and clears the draft', (t) async {
    await pump(t);
    await t.enterText(find.byKey(AppKeys.mobileComposerField), 'ls -la');
    await t.tap(find.byKey(AppKeys.mobileComposerSendButton));
    await t.pump();
    expect(String.fromCharCodes(sent.single), 'ls -la\r');
    expect(controller.text, isEmpty);
  });

  testWidgets('Return-mode off sends the text bare', (t) async {
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerSubmitToggle));
    await t.pump();
    await t.enterText(find.byKey(AppKeys.mobileComposerField), 'ls -la');
    await t.tap(find.byKey(AppKeys.mobileComposerSendButton));
    await t.pump();
    expect(String.fromCharCodes(sent.single), 'ls -la');
    expect(cubit.state.chatMode, isFalse);
  });

  testWidgets('send with an empty draft presses Return', (t) async {
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerSendButton));
    await t.pump();
    expect(sent, [
      [0x0d],
    ]);
  });

  testWidgets('close returns the bottom slot to the key bar', (t) async {
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerCloseButton));
    await t.pump();
    expect(cubit.state.mode, MobileInputMode.keys);
  });

  testWidgets('the draft is not owned by the panel', (t) async {
    await pump(t);
    await t.enterText(find.byKey(AppKeys.mobileComposerField), 'half typed');
    // Unmounting the panel is what happens when the user switches to the key
    // bar; the caller's controller must survive it.
    await t.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(controller.text, 'half typed');
  });
}
