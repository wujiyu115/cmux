import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/terminal_transport.dart';

/// Input-origin tracking for the Bark push gate: desktop keystrokes flow
/// TerminalView → engine.output → PTY (local), phone keystrokes flow pairing
/// InputFrame → writeRemoteInput (remote). `lastInputWasRemote` compares the
/// two timestamps.
class _FakeTransport implements TerminalTransport {
  final outputController = StreamController<Uint8List>.broadcast();
  final doneCompleter = Completer<int>();
  @override
  Stream<Uint8List> get output => outputController.stream;
  @override
  Future<int> get done => doneCompleter.future;
  @override
  int? get pid => null;
  @override
  void close() {
    if (!doneCompleter.isCompleted) doneCompleter.complete(0);
  }

  @override
  void resize(int rows, int columns) {}

  @override
  void write(Uint8List data) {}
}

void main() {
  ({TerminalSession session, List<Uint8List> local, List<Uint8List> remote})
  build() {
    final local = <Uint8List>[];
    final remote = <Uint8List>[];
    final session = TerminalSession(
      executable: Platform.resolvedExecutable,
      transportStarter: (executable,
          {required arguments,
          required workingDirectory,
          required columns,
          required rows,
          environment}) {
        return Future.value(_FakeTransport());
      },
    );
    return (session: session, local: local, remote: remote);
  }

  test('no input yet reports local (not remote)', () {
    final b = build();
    addTearDown(b.session.dispose);
    expect(b.session.lastInputWasRemote, isFalse);
  });

  test('remote input marks the session remote', () {
    final b = build();
    addTearDown(b.session.dispose);

    b.session.writeRemoteInput(Uint8List.fromList([0x61]));

    expect(b.session.lastInputWasRemote, isTrue);
  });

  test('local input after remote flips the origin back', () {
    final b = build();
    addTearDown(b.session.dispose);

    b.session.writeRemoteInput(Uint8List.fromList([0x61]));
    expect(b.session.lastInputWasRemote, isTrue);

    // Desktop keystroke path: engine.output → the wired listener → PTY.
    // Local must land strictly after remote, so wait a clock tick.
    sleep(const Duration(milliseconds: 2));
    b.session.engine.write(Uint8List.fromList([0x62]));
    expect(b.session.lastInputWasRemote, isFalse);
  });

  test('local input alone never reports remote', () {
    final b = build();
    addTearDown(b.session.dispose);

    b.session.engine.write(Uint8List.fromList([0x63]));

    expect(b.session.lastInputWasRemote, isFalse);
  });
}
