import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/storage/remote_file_store.dart';

const _profile = SshProfile(
  id: 'p1',
  name: 'dev',
  host: 'example.com',
  username: 'alice',
);

SshClientFactory _factory(_RecordingSshClient client) => SshClientFactory(
  credentialStore: InMemorySshCredentialStore(),
  knownHostRepository: InMemorySshKnownHostRepository(),
  connector: (profile, {timeout = const Duration(seconds: 10)}) async =>
      client,
);

class _RecordingSshClient extends SSHClient {
  _RecordingSshClient(this.result) : super(_FakeSSHSocket(), username: 'test');

  final SSHRunResult result;
  final commands = <String>[];

  @override
  Future<void> get authenticated => Future.value();

  @override
  Future<SSHRunResult> runWithResult(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
  }) async {
    commands.add(command);
    return result;
  }
}

SSHRunResult _result(
  String stdout, {
  int? exitCode,
}) => SSHRunResult(
  output: Uint8List(0),
  stdout: Uint8List.fromList(utf8.encode(stdout)),
  stderr: Uint8List(0),
  exitCode: exitCode,
  exitSignal: null,
);

class _FakeSSHSocket implements SSHSocket {
  final _inputController = StreamController<Uint8List>();
  final _doneCompleter = Completer<void>();

  @override
  Stream<Uint8List> get stream => _inputController.stream;

  @override
  StreamSink<List<int>> get sink => _NoopSink();

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    await _inputController.close();
  }

  @override
  void destroy() {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    unawaited(_inputController.close());
  }
}

class _NoopSink implements StreamSink<List<int>> {
  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final _ in stream) {}
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> get done async {}
}

void main() {
  // Regression: a relative template made mktemp create the directory in the
  // login shell's cwd and return a *relative* path, which the phone then
  // couldn't read back (e.g. `teampilot-upload-714Vzu/…`).
  test('asks mktemp for an absolute /tmp template and returns its output', () async {
    final client = _RecordingSshClient(
      _result('/tmp/teampilot-upload-714Vzu\n'),
    );
    final store = RemoteFileStore(
      profile: _profile,
      clientFactory: _factory(client),
    );

    final dir = await store.createTempDir(prefix: 'teampilot-upload-');

    expect(client.commands, ["mktemp -d -- '/tmp/teampilot-upload-XXXXXX'"]);
    expect(dir, '/tmp/teampilot-upload-714Vzu');
  });

  test('honors an explicit parent', () async {
    final client = _RecordingSshClient(_result('/var/cache/tmp-x1\n'));
    final store = RemoteFileStore(
      profile: _profile,
      clientFactory: _factory(client),
    );

    await store.createTempDir(parent: '/var/cache');

    expect(client.commands, ["mktemp -d -- '/var/cache/tmpXXXXXX'"]);
  });

  test('throws when mktemp fails', () async {
    final client = _RecordingSshClient(
      _result('', exitCode: 1),
    );
    final store = RemoteFileStore(
      profile: _profile,
      clientFactory: _factory(client),
    );

    await expectLater(store.createTempDir(), throwsStateError);
  });
}
