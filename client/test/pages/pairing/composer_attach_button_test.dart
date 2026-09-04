import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/media_upload_cubit.dart';
import 'package:teampilot/services/pairing/upload_source.dart';
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
  List<PickedMedia> next = const [];
  int calls = 0;

  Future<List<PickedMedia>> pick() async {
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
  int cancels = 0;

  /// Records the request and leaves the upload pending.
  ///
  /// Deliberately does not fail the future: what the transport does after being
  /// told to stop, and how the cubit reports it, is
  /// `media_upload_cubit_test.dart`'s subject. Here the question is only whether
  /// the chip is wired to `cancel` and what it renders once cancelling.
  void cancel() => cancels++;

  Future<String> upload({
    required String filename,
    required UploadSource source,
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
  late MediaUploadCubit upload;
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
    upload = MediaUploadCubit(
      pickMedia: picker.pick,
      upload: uploader.upload,
      cancelUpload: uploader.cancel,
    );
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

  PickedMedia smallImage() => PickedMedia(
    filename: 'photo.jpg',
    source: MemoryUploadSource(Uint8List(10)),
  );

  testWidgets('shows the attach button when idle', (t) async {
    await pump(t);
    expect(find.byKey(AppKeys.mobileComposerAttachButton), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('tapping the attach button invokes the picker', (t) async {
    picker.next = const []; // Backing out of the sheet returns to idle.
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerAttachButton));
    await t.pump();
    await t.pump();
    expect(picker.calls, 1);
  });

  /// Taps attach and drives the cubit to `uploading` with the upload held open.
  Future<void> startUpload(WidgetTester t) async {
    picker.next = [smallImage()];
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerAttachButton));
    // picking → uploading; the upload future is held open by the completer.
    await t.pump();
    await t.pump();
  }

  testWidgets('shows a determinate spinner while uploading', (t) async {
    await startUpload(t);
    uploader.onProgress?.call(5, 10);
    await t.pump();

    final indicator = t.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    // Determinate on purpose: the byte count is known during an upload.
    expect(indicator.value, isNotNull);
    expect(indicator.value, 0.5);
    // The + is replaced by the ring, so it is gone while uploading.
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byKey(AppKeys.mobileComposerAttachButton), findsNothing);
  });

  testWidgets('shows the percentage and byte figures while uploading', (
    t,
  ) async {
    // A video can take minutes on a LAN; the ring alone cannot tell a slow
    // transfer from a stalled one. The figures come from the batch counters,
    // so the picked file's claimed length is the 10 MiB the ticks report
    // against.
    picker.next = [
      PickedMedia(
        filename: 'clip.mp4',
        source: _HugeSource(10 * 1024 * 1024),
      ),
    ];
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerAttachButton));
    await t.pump();
    await t.pump();
    uploader.onProgress?.call(5 * 1024 * 1024, 10 * 1024 * 1024);
    await t.pump();

    expect(find.text('50% · 5/10 MB'), findsOneWidget);
  });

  testWidgets('the uploading chip cancels, and cancelling drops the key', (
    t,
  ) async {
    await startUpload(t);
    expect(
      find.byKey(AppKeys.mobileComposerCancelUploadButton),
      findsOneWidget,
    );

    await t.tap(find.byKey(AppKeys.mobileComposerCancelUploadButton));
    await t.pump();

    expect(uploader.cancels, 1);
    // Cancelling: no longer tappable, and the ring stops claiming a figure.
    expect(find.byKey(AppKeys.mobileComposerCancelUploadButton), findsNothing);
    final indicator = t.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, isNull);
    expect(find.textContaining('MB'), findsNothing);
  });

  testWidgets('emits the host path once the upload commits', (t) async {
    // A fresh cubit whose upload resolves immediately with the host path. The
    // spinner test already covers the in-flight state, so here we only need the
    // committed path to reach the stream.
    await upload.close();
    upload = MediaUploadCubit(
      pickMedia: picker.pick,
      upload: ({required filename, required source, onProgress}) async =>
          '/Users/me/proj/photo.jpg',
    );
    picker.next = [smallImage()];
    await pump(t);
    // Collect into a variable rather than awaiting paths.first: paths is an
    // async broadcast stream, so a missing emit should fail the assert, not
    // hang the test on a future that never completes.
    final emitted = <String>[];
    final sub = upload.paths.listen(emitted.add);
    addTearDown(sub.cancel);
    await t.tap(find.byKey(AppKeys.mobileComposerAttachButton));
    await t.pump();
    await t.pump();
    await t.pump();
    // The mirror page is what quotes and inserts this; here we only assert the
    // host's path reaches the stream. shell_quote_test covers the quoting.
    expect(emitted, ['/Users/me/proj/photo.jpg']);
  });

  testWidgets('a multi pick emits one path per file, in pick order', (t) async {
    await upload.close();
    upload = MediaUploadCubit(
      pickMedia: picker.pick,
      upload: ({required filename, required source, onProgress}) async =>
          '/Users/me/proj/$filename',
    );
    picker.next = [
      PickedMedia(filename: 'a.png', source: MemoryUploadSource(Uint8List(4))),
      PickedMedia(filename: 'b.mp4', source: MemoryUploadSource(Uint8List(6))),
    ];
    await pump(t);
    final emitted = <String>[];
    final sub = upload.paths.listen(emitted.add);
    addTearDown(sub.cancel);
    await t.tap(find.byKey(AppKeys.mobileComposerAttachButton));
    await t.pump();
    await t.pump();
    await t.pump();
    expect(emitted, ['/Users/me/proj/a.png', '/Users/me/proj/b.mp4']);
  });

  testWidgets('an oversized image names the image cap', (t) async {
    // The local guard trips before any transfer, and the number now travels with
    // the failure rather than being a default on the messenger.
    picker.next = [
      PickedMedia(
        filename: 'huge.png',
        source: MemoryUploadSource(Uint8List(26 * 1024 * 1024)),
      ),
    ];
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerAttachButton));
    await t.pump();
    await t.pump();
    expect(find.text('Image is larger than 25 MB'), findsOneWidget);
  });

  testWidgets('an oversized video names the video cap', (t) async {
    picker.next = [
      PickedMedia(filename: 'huge.mp4', source: _HugeSource(513 * 1024 * 1024)),
    ];
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerAttachButton));
    await t.pump();
    await t.pump();
    expect(find.text('Video is larger than 512 MB'), findsOneWidget);
  });

  testWidgets('an unsupported type raises its snack bar', (t) async {
    picker.next = [smallImage()];
    uploader.error = const PairingUploadException('unsupported_type');
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerAttachButton));
    await t.pump();
    await t.pump();
    await t.pump();
    expect(find.text('That file type is not supported'), findsOneWidget);
  });

  testWidgets('any other failure raises the generic snack bar', (t) async {
    picker.next = [smallImage()];
    uploader.error = const PairingUploadException('boom');
    await pump(t);
    await t.tap(find.byKey(AppKeys.mobileComposerAttachButton));
    await t.pump();
    await t.pump();
    await t.pump();
    expect(find.text('Upload failed'), findsOneWidget);
  });
}

/// Claims a huge length without allocating it — a 513 MiB Uint8List in a widget
/// test is pointless when only `length` is ever read.
class _HugeSource implements UploadSource {
  _HugeSource(this.length);

  @override
  final int length;

  @override
  Future<Uint8List> read(int maxBytes) async => Uint8List(0);

  @override
  Future<void> close() async {}
}
