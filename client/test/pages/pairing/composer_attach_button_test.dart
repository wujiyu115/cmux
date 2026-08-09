import 'dart:async';
import 'dart:typed_data';

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
import 'package:teampilot/services/pairing/pairing_upload_sender.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/fake_stt_provider.dart';

/// A stand-in photo picker. Returns whatever [next] is set to and counts calls.
class _FakePicker {
  PickedImage? next;
  int calls = 0;

  Future<PickedImage?> pick() async {
    calls++;
    return next;
  }
}

/// A stand-in uploader. Hands back a controllable future so a test can hold the
/// upload in flight (to observe the spinner), complete it (to observe the path),
/// or fail it (to observe a snack bar).
class _FakeUploader {
  final completer = Completer<String>();
  void Function(int sent, int total)? onProgress;
  Object? error;

  Future<String> upload({
    required String filename,
    required Uint8List bytes,
    void Function(int sent, int total)? onProgress,
  }) {
    this.onProgress = onProgress;
    if (error != null) return Future.error(error!);
    return completer.future;
  }
}

void main() {
  late MobileToolbarCubit toolbar;
  late VoiceInputCubit voice;
  late ImageUploadCubit upload;
  late _FakePicker picker;
  late _FakeUploader uploader;
  late TextEditingController controller;
  late FocusNode focusNode;

  setUp(() {
    toolbar = MobileToolbarCubit(
      repository: InMemoryMobileToolbarRepository(),
      sendInput: (_) {},
      readClipboard: () async => null,
      usageFlushDelay: const Duration(milliseconds: 10),
    );
    // No backend loaded, so the mic stays hidden and does not muddy the row.
    voice = VoiceInputCubit(
      repository: InMemoryVoiceInputRepository(),
      providerFactory: (_, _) => FakeSttProvider(),
    );
    picker = _FakePicker();
    uploader = _FakeUploader();
    upload = ImageUploadCubit(pickImage: picker.pick, upload: uploader.upload);
    controller = TextEditingController();
    focusNode = FocusNode();
  });

  tearDown(() async {
    await toolbar.close();
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

  PickedImage smallImage() =>
      PickedImage(filename: 'photo.jpg', bytes: Uint8List(10));

  testWidgets('shows the attach button when idle', (t) async {
    await pump(t);
    expect(find.byKey(AppKeys.mobileComposerAttachButton), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('tapping the attach button invokes the picker', (t) async {
    picker.next = null; // Backing out of the sheet returns to idle.
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerAttachButton));
    await t.pump();
    await t.pump();
    expect(picker.calls, 1);
  });

  testWidgets('shows a determinate spinner while uploading', (t) async {
    picker.next = smallImage();
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerAttachButton));
    // picking → uploading; the upload future is held open by the completer.
    await t.pump();
    await t.pump();
    uploader.onProgress?.call(5, 10);
    await t.pump();

    final indicator = t.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    // Determinate on purpose: the byte count is known during an upload.
    expect(indicator.value, isNotNull);
    expect(indicator.value, 0.5);
    // The + is replaced by the spinner, so it is gone while uploading.
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byKey(AppKeys.mobileComposerAttachButton), findsNothing);
  });

  testWidgets('emits the host path once the upload commits', (t) async {
    // A fresh cubit whose upload resolves immediately with the host path. The
    // spinner test already covers the in-flight state, so here we only need the
    // committed path to reach the stream.
    await upload.close();
    upload = ImageUploadCubit(
      pickImage: picker.pick,
      upload: ({required filename, required bytes, onProgress}) async =>
          '/Users/me/proj/photo.jpg',
    );
    picker.next = smallImage();
    await pump(t);
    // Collect into a variable rather than awaiting paths.first: paths is an
    // async broadcast stream, so a missing emit should fail the assert, not
    // hang the test on a future that never completes.
    String? emitted;
    final sub = upload.paths.listen((p) => emitted = p);
    addTearDown(sub.cancel);
    await t.tap(find.byKey(AppKeys.mobileComposerAttachButton));
    await t.pump();
    await t.pump();
    await t.pump();
    // The mirror page is what quotes and inserts this; here we only assert the
    // host's path reaches the stream. shell_quote_test covers the quoting.
    expect(emitted, '/Users/me/proj/photo.jpg');
  });

  testWidgets('an oversized image raises the too-large snack bar', (t) async {
    // maxBytes below the picked size trips the local guard before any transfer.
    await upload.close();
    upload = ImageUploadCubit(
      pickImage: picker.pick,
      upload: uploader.upload,
      maxBytes: 4,
    );
    picker.next = smallImage();
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerAttachButton));
    await t.pump();
    await t.pump();
    // The 25 comes from UploadFailureMessenger's default maxMb, not maxBytes.
    expect(find.text('Image is larger than 25 MB'), findsOneWidget);
  });

  testWidgets('an unsupported type raises its snack bar', (t) async {
    picker.next = smallImage();
    uploader.error = const PairingUploadException('unsupported_type');
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerAttachButton));
    await t.pump();
    await t.pump();
    await t.pump();
    expect(find.text('That image type is not supported'), findsOneWidget);
  });

  testWidgets('any other failure raises the generic snack bar', (t) async {
    picker.next = smallImage();
    uploader.error = const PairingUploadException('boom');
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerAttachButton));
    await t.pump();
    await t.pump();
    await t.pump();
    expect(find.text('Image upload failed'), findsOneWidget);
  });
}
