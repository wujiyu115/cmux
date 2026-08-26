import 'dart:typed_data';

import 'package:teampilot/services/pairing/pairing_upload_target.dart';

/// Records what a transfer wrote without touching a filesystem.
///
/// Every method is instrumented and every failure is injectable, because the
/// receiver's interesting behaviour is all about *when* it calls these — the
/// withheld ack, the tail append before commit, abort inside the transfer lock.
class FakeUploadTarget implements PairingUploadTarget {
  FakeUploadTarget({
    this.path = '/home/dev/app/photo.jpg',
    this.preferredFlushBytes = 1024,
  });

  /// What [commit] returns.
  String path;

  @override
  int preferredFlushBytes;

  /// Every [append]'s payload, in the order they landed.
  final List<Uint8List> appends = [];

  /// Ordered method-name log, so a test can assert the tail append happened
  /// *before* the commit rather than merely that both happened.
  final List<String> calls = [];

  int commitCount = 0;
  int abortCount = 0;

  Object? appendError;
  Object? commitError;

  /// Completed by a test to release a held [append], which is how the ack
  /// backpressure invariant is observed.
  Future<void>? holdAppend;

  int get appendedBytes =>
      appends.fold(0, (sum, chunk) => sum + chunk.length);

  @override
  Future<void> append(List<int> bytes) async {
    calls.add('append');
    final hold = holdAppend;
    if (hold != null) await hold;
    final error = appendError;
    if (error != null) throw error;
    appends.add(Uint8List.fromList(bytes));
  }

  @override
  Future<String> commit() async {
    calls.add('commit');
    commitCount++;
    final error = commitError;
    if (error != null) throw error;
    return path;
  }

  @override
  Future<void> abort() async {
    calls.add('abort');
    abortCount++;
  }
}

/// Hands out [FakeUploadTarget]s and records the arguments it was opened with.
class FakeUploadOpener {
  FakeUploadOpener({this.target});

  /// Reused for every open when set, so a test can inspect one target without
  /// having to fish it out of [opens].
  FakeUploadTarget? target;

  Object? openError;

  final List<({String workspaceId, String cwd, String filename})> opens = [];
  final List<FakeUploadTarget> handedOut = [];

  Future<PairingUploadTarget> call({
    required String workspaceId,
    required String cwd,
    required String filename,
  }) async {
    opens.add((workspaceId: workspaceId, cwd: cwd, filename: filename));
    final error = openError;
    if (error != null) throw error;
    final out = target ?? FakeUploadTarget();
    handedOut.add(out);
    return out;
  }
}

/// An opener for tests that only need the handler to construct, not to upload.
Future<PairingUploadTarget> noopUploadOpener({
  required String workspaceId,
  required String cwd,
  required String filename,
}) async => FakeUploadTarget();
