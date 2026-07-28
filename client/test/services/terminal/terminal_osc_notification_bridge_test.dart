import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/models/app_notification.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';
import 'package:teampilot/services/terminal/terminal_osc_notification_bridge.dart';

const _esc = '\x1b';
const _bel = '\x07';

typedef _Row = ({
  String title,
  String message,
  String payload,
  TpToastVariant variant,
  AppNotificationSource source,
});

class _RecordingRecorder implements NotificationRecorder {
  final rows = <_Row>[];

  @override
  void record({
    required String message,
    required TpToastVariant variant,
    String title = '',
    String payload = '',
    AppNotificationSource source = AppNotificationSource.app,
  }) {
    rows.add((
      title: title,
      message: message,
      payload: payload,
      variant: variant,
      source: source,
    ));
  }
}

TerminalOscNotificationBridge _bridge(
  _RecordingRecorder recorder, {
  String attribution = 'acme · shell 1',
}) => TerminalOscNotificationBridge(
  attribution: () => attribution,
  payload: () => '/home-v2/workspace/w1',
  recorder: recorder,
);

void main() {
  test('OSC 9 body becomes an osc9 row titled by attribution', () async {
    final recorder = _RecordingRecorder();
    final notify = StreamController<String>();
    _bridge(recorder).observeEngineNotify(notify.stream);

    notify.add('build finished');
    await pumpEventQueue();

    expect(recorder.rows.single.source, AppNotificationSource.osc9);
    expect(recorder.rows.single.title, 'acme · shell 1');
    expect(recorder.rows.single.message, 'build finished');
    expect(recorder.rows.single.payload, '/home-v2/workspace/w1');
  });

  test('OSC 777 splits title and body at the NUL separator', () async {
    final recorder = _RecordingRecorder();
    final notify = StreamController<String>();
    _bridge(recorder).observeEngineNotify(notify.stream);

    notify.add(
      'Deploy${TerminalOscNotificationBridge.osc777Separator}staging is live',
    );
    await pumpEventQueue();

    expect(recorder.rows.single.source, AppNotificationSource.osc777);
    expect(recorder.rows.single.title, 'acme · shell 1 · Deploy');
    expect(recorder.rows.single.message, 'staging is live');
  });

  test('attribution is omitted when nothing is known', () async {
    final recorder = _RecordingRecorder();
    final notify = StreamController<String>();
    _bridge(recorder, attribution: '  ').observeEngineNotify(notify.stream);

    notify.add('bare');
    await pumpEventQueue();

    expect(recorder.rows.single.title, '');
  });

  test('OSC 99 title-only report is promoted to the message', () {
    final recorder = _RecordingRecorder();
    _bridge(recorder).observePtyText('$_esc]99;i=1:p=title;Tests passed$_bel');

    expect(recorder.rows.single.source, AppNotificationSource.osc99);
    expect(recorder.rows.single.title, 'acme · shell 1');
    expect(recorder.rows.single.message, 'Tests passed');
  });

  test('OSC 99 chunks with d=0 accumulate into one row', () {
    final recorder = _RecordingRecorder();
    final bridge = _bridge(recorder);

    bridge.observePtyText('$_esc]99;i=7:d=0:p=title;Suite$_bel');
    bridge.observePtyText('$_esc]99;i=7:d=0:p=body;12 tests, $_bel');
    expect(recorder.rows, isEmpty);

    bridge.observePtyText('$_esc]99;i=7:p=body;0 failures$_bel');
    expect(recorder.rows.single.title, 'acme · shell 1 · Suite');
    expect(recorder.rows.single.message, '12 tests, 0 failures');
  });

  test('OSC 99 urgency 2 maps to the error variant', () {
    final recorder = _RecordingRecorder();
    _bridge(recorder).observePtyText('$_esc]99;u=2;disk full$_bel');

    expect(recorder.rows.single.variant, TpToastVariant.error);
    expect(
      _bridgeVariantForUrgency(recorder, '$_esc]99;u=1;ok$_bel'),
      TpToastVariant.success,
    );
  });

  test('unrelated OSC codes and empty bodies raise nothing', () {
    final recorder = _RecordingRecorder();
    final bridge = _bridge(recorder);
    bridge.observePtyText('$_esc]0;window title$_bel');
    bridge.observePtyText('$_esc]133;C$_bel');
    bridge.observePtyText('$_esc]99;i=3;$_bel');
    expect(recorder.rows, isEmpty);
  });

  test('control characters in the payload are neutralised', () {
    final recorder = _RecordingRecorder();
    _bridge(recorder).observePtyText('$_esc]99;;line$_bel');
    // A BEL inside the payload terminates the sequence, so feed a tab instead.
    _bridge(recorder).observePtyText('$_esc]99;;a\tb$_bel');

    expect(recorder.rows.last.message, 'a b');
  });

  test('long bodies are clamped with an ellipsis', () {
    final recorder = _RecordingRecorder();
    final body = 'x' * (TerminalOscNotificationBridge.maxBodyChars + 50);
    _bridge(recorder).observePtyText('$_esc]99;;$body$_bel');

    final message = recorder.rows.single.message;
    expect(message.length, TerminalOscNotificationBridge.maxBodyChars + 1);
    expect(message.endsWith('…'), isTrue);
  });

  test('dispose stops both feeds', () async {
    final recorder = _RecordingRecorder();
    final notify = StreamController<String>();
    final bridge = _bridge(recorder)..observeEngineNotify(notify.stream);

    bridge.dispose();
    notify.add('after dispose');
    bridge.observePtyText('$_esc]99;;also after$_bel');
    await pumpEventQueue();

    expect(recorder.rows, isEmpty);
  });
}

TpToastVariant _bridgeVariantForUrgency(
  _RecordingRecorder recorder,
  String data,
) {
  final before = recorder.rows.length;
  _bridge(recorder).observePtyText(data);
  expect(recorder.rows.length, before + 1);
  return recorder.rows.last.variant;
}
