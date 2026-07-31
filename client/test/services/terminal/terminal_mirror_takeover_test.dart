import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/terminal_transport.dart';

import 'dart:async';

class _FakeTransport implements TerminalTransport {
  final _output = StreamController<Uint8List>();
  final _done = Completer<int>();
  @override
  Stream<Uint8List> get output => _output.stream;
  @override
  Future<int> get done => _done.future;
  @override
  int? get pid => null;
  @override
  void close() {
    if (!_done.isCompleted) _done.complete(0);
  }

  @override
  void resize(int rows, int columns) {}
  @override
  void write(Uint8List data) {}
}

void main() {
  TerminalSession makeSession() => TerminalSession(
    executable: 'true',
    validateLaunch: false,
    parseExecutable: false,
    transportStarter:
        (
          executable, {
          required arguments,
          required workingDirectory,
          required columns,
          required rows,
          environment,
        }) => Future.value(_FakeTransport()),
  );

  test('takeover is null until a phone attaches', () {
    final session = makeSession();
    addTearDown(session.dispose);
    expect(session.mirrorTakeover.value, isNull);
  });

  test('two phones refcount up; last detach clears the takeover', () {
    final session = makeSession();
    addTearDown(session.dispose);

    session.attachMirror();
    expect(session.mirrorTakeover.value?.viewers, 1);

    session.attachMirror();
    expect(session.mirrorTakeover.value?.viewers, 2);

    session.detachMirror();
    expect(session.mirrorTakeover.value?.viewers, 1);

    session.detachMirror();
    expect(session.mirrorTakeover.value, isNull);
  });

  test('detach with no takeover is a no-op', () {
    final session = makeSession();
    addTearDown(session.dispose);
    session.detachMirror();
    expect(session.mirrorTakeover.value, isNull);
  });

  test('pty resize while taken over updates the banner grid', () {
    final session = makeSession();
    addTearDown(session.dispose);

    session.attachMirror();
    session.onTerminalPtyResize(84, 67);
    expect(session.mirrorTakeover.value?.cols, 84);
    expect(session.mirrorTakeover.value?.rows, 67);
  });

  test('pty resize while not taken over touches nothing', () {
    final session = makeSession();
    addTearDown(session.dispose);
    session.onTerminalPtyResize(84, 67);
    expect(session.mirrorTakeover.value, isNull);
  });

  test('notifies listeners on attach and final detach', () {
    final session = makeSession();
    addTearDown(session.dispose);
    var notifications = 0;
    session.mirrorTakeover.addListener(() => notifications++);

    session.attachMirror();
    session.detachMirror();
    expect(notifications, 2);
  });
}
