import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/pairing_client_cubit.dart';
import 'package:teampilot/repositories/pairing_settings_repository.dart';
import 'package:teampilot/services/pairing/pairing_client.dart';
import 'package:teampilot/services/pairing/pairing_offer.dart';
import 'package:teampilot/services/pairing/pairing_upload_sender.dart';

/// Hand-rolled fake so the cubit runs its full flow without a real socket.
class _FakePairingClient extends PairingClient {
  _FakePairingClient({
    this.result = const PairingAuthResult(
      deviceId: 'device-1',
      hostName: 'My Desktop',
      deviceToken: 'token-1',
    ),
    this.sessions = const [],
    this.workspaces = const [],
    this.connectError,
    this.activateError,
    this.activateResult = const PairingActivateResult(
      catalogId: 'ws:p1',
      cols: 80,
      rows: 24,
    ),
  });

  final PairingAuthResult result;
  final List<PairingSessionSummary> sessions;
  List<PairingWorkspaceNode> workspaces;
  final Object? connectError;
  final Object? activateError;
  final PairingActivateResult activateResult;

  final _logCtrl = StreamController<String>.broadcast();
  final _stageCtrl = StreamController<PairingStageEvent>.broadcast();
  final _changedCtrl = StreamController<void>.broadcast();
  final List<(int, Uint8List)> sentInput = [];
  final List<(int, int, int)> sentResize = [];
  final List<(int, String, Uint8List)> uploads = [];
  String uploadPath = '/home/me/pics/photo.png';
  final List<int> unsubscribed = [];
  int listWorkspacesCalls = 0;
  bool closed = false;

  void pushSessionsChanged() => _changedCtrl.add(null);

  @override
  Stream<String> get log => _logCtrl.stream;

  @override
  Stream<PairingStageEvent> get stages => _stageCtrl.stream;

  @override
  Stream<void> get sessionsChanged => _changedCtrl.stream;

  @override
  Future<PairingAuthResult> connect({
    required List<String> wsUrls,
    required String token,
    required String hostPublicKeyB64,
    String? deviceId,
    String deviceName = 'Mobile device',
  }) async {
    _logCtrl.add('Connecting…');
    // Mirrors the real client's stage emissions so the cubit's rail state and
    // failure attribution are exercised.
    _stage(PairingStage.connect, PairingStageStatus.active);
    if (connectError != null) throw connectError!;
    _stage(PairingStage.connect, PairingStageStatus.done);
    _stage(PairingStage.secureChannel, PairingStageStatus.active);
    _stage(PairingStage.secureChannel, PairingStageStatus.done);
    _stage(PairingStage.authenticate, PairingStageStatus.active);
    _stage(PairingStage.authenticate, PairingStageStatus.done);
    connectedUrl = wsUrls.isEmpty ? null : wsUrls.first;
    return result;
  }

  void _stage(PairingStage stage, PairingStageStatus status) =>
      _stageCtrl.add(PairingStageEvent(stage, status));

  @override
  Future<List<PairingSessionSummary>> listSessions() async => sessions;

  @override
  Future<List<PairingWorkspaceNode>> listWorkspaces() async {
    listWorkspacesCalls++;
    return workspaces;
  }

  @override
  Future<PairingActivateResult> activateSession({
    required String workspaceId,
    String? paneId,
  }) async {
    if (activateError != null) throw activateError!;
    return activateResult;
  }

  @override
  Future<PairingSubscription> subscribe(String catalogId) async {
    final controller = StreamController<Uint8List>.broadcast();
    addTearDown(controller.close);
    return PairingSubscription(42, controller);
  }

  @override
  void unsubscribe(int sub) => unsubscribed.add(sub);

  @override
  void sendInput(int sub, Uint8List data) => sentInput.add((sub, data));

  @override
  void sendResize(int sub, int cols, int rows) =>
      sentResize.add((sub, cols, rows));

  @override
  Future<String> uploadFile({
    required int sub,
    required String filename,
    required Uint8List bytes,
    void Function(int sent, int total)? onProgress,
  }) async {
    uploads.add((sub, filename, bytes));
    return uploadPath;
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_logCtrl.isClosed) await _logCtrl.close();
    if (!_stageCtrl.isClosed) await _stageCtrl.close();
    if (!_changedCtrl.isClosed) await _changedCtrl.close();
  }
}

PairingWorkspaceNode _wsNode({
  String id = 'wsA',
  List<PairingSessionNode> panes = const [],
}) => PairingWorkspaceNode(
  workspaceId: id,
  title: 'Workspace A',
  panes: panes,
);

PairingOffer _makeOffer() => const PairingOffer(
  version: 1,
  wsUrls: ['ws://192.168.1.9:5555/pair/ws'],
  token: 'code',
  hostPublicKeyB64: 'PK',
  expiresAtMs: 0,
);

void main() {
  group('PairingClientCubit', () {
    test('loadPairedDesktops seeds the state list', () async {
      final settings = InMemoryPairingSettingsRepository(
        pairedDesktops: const [
          PairedDesktop(
            id: 'd1',
            name: 'Home',
            wsUrls: ['ws://x'],
            hostPublicKeyB64: 'pk',
            deviceToken: 't',
          ),
        ],
      );
      final cubit = PairingClientCubit(settings: settings);
      addTearDown(cubit.close);
      await cubit.loadPairedDesktops();
      expect(cubit.state.pairedDesktops, hasLength(1));
      expect(cubit.state.pairedDesktops.single.name, 'Home');
    });

    test('happy path: idle → confirming → connected, persists desktop',
        () async {
      final settings = InMemoryPairingSettingsRepository();
      final fake = _FakePairingClient(
        result: const PairingAuthResult(
          deviceId: 'device-1',
          hostName: 'My Desktop',
          deviceToken: 'token-1',
        ),
        workspaces: [
          _wsNode(
            panes: const [
              PairingSessionNode(
                workspaceId: 'wsA',
                title: 'shell',
                subtitle: '',
                live: true,
                paneId: 'p1',
                catalogId: 'ws:p1',
              ),
            ],
          ),
        ],
      );
      final cubit = PairingClientCubit(
        settings: settings,
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);

      cubit.beginPairing(_makeOffer());
      expect(cubit.state.phase, PairingClientPhase.confirmAwaiting);

      final phases = expectLater(
        cubit.stream.map((s) => s.phase),
        emitsThrough(PairingClientPhase.connected),
      );
      await cubit.confirmPairing();
      await phases;

      expect(cubit.state.phase, PairingClientPhase.connected);
      expect(cubit.state.activeHostName, 'My Desktop');
      expect(cubit.state.workspaces, hasLength(1));
      expect(cubit.state.workspaces.single.panes, hasLength(1));
      expect(cubit.state.pendingOffer, isNull);

      final saved = await settings.loadPairedDesktops();
      expect(saved, hasLength(1));
      expect(saved.single.id, 'device-1');
      expect(saved.single.deviceToken, 'token-1');
    });

    test('connect failure moves to error phase and logs it', () async {
      final settings = InMemoryPairingSettingsRepository();
      final fake = _FakePairingClient(connectError: Exception('boom'));
      final cubit = PairingClientCubit(
        settings: settings,
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);

      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();

      expect(cubit.state.phase, PairingClientPhase.error);
      expect(cubit.state.error, contains('boom'));
      expect(cubit.state.logs.any((l) => l.contains('Error')), isTrue);
      expect(fake.closed, isTrue);
      expect(await settings.loadPairedDesktops(), isEmpty);
    });

    test('a successful connect walks every stage to done', () async {
      final fake = _FakePairingClient();
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);

      cubit.beginPairing(_makeOffer());
      expect(cubit.state.stageStatuses, PairingClientState.idleStages);

      await cubit.confirmPairing();
      await Future<void>.delayed(Duration.zero);

      expect(
        cubit.state.stageStatuses,
        List.filled(PairingStage.values.length, PairingStageStatus.done),
      );
      expect(cubit.state.activeHostUrl, 'ws://192.168.1.9:5555/pair/ws');
    });

    test('a thrown connect fails the stage that was in flight', () async {
      final fake = _FakePairingClient(connectError: Exception('no route'));
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);

      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();
      await Future<void>.delayed(Duration.zero);

      expect(
        cubit.state.stageStatuses[PairingStage.connect.index],
        PairingStageStatus.fail,
      );
      // Later stages never started, so they stay untouched.
      expect(
        cubit.state.stageStatuses[PairingStage.authenticate.index],
        PairingStageStatus.idle,
      );
    });

    test('both connect paths stamp lastConnectedAt', () async {
      final settings = InMemoryPairingSettingsRepository();
      final cubit = PairingClientCubit(
        settings: settings,
        clientFactory: _FakePairingClient.new,
      );
      addTearDown(cubit.close);

      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();
      final firstStamp = (await settings.loadPairedDesktops()).single
          .lastConnectedAt;
      expect(firstStamp, isNotNull);

      final stored = cubit.state.pairedDesktops.single.copyWith(
        lastConnectedAt: DateTime(2020),
      );
      await settings.savePairedDesktops([stored]);
      await cubit.connectToDesktop(stored);

      final reconnected = (await settings.loadPairedDesktops()).single;
      expect(reconnected.lastConnectedAt!.isAfter(DateTime(2020)), isTrue);
    });

    test('reconnect names the host before the handshake finishes', () async {
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => _FakePairingClient(connectError: Exception('x')),
      );
      addTearDown(cubit.close);

      await cubit.connectToDesktop(
        const PairedDesktop(
          id: 'd1',
          name: 'Studio',
          wsUrls: ['ws://x'],
          hostPublicKeyB64: 'pk',
          deviceToken: 't',
        ),
      );

      expect(cubit.state.activeHostName, 'Studio');
    });

    test('restoreDesktop puts back a removed desktop once', () async {
      const desktop = PairedDesktop(
        id: 'd1',
        name: 'Home',
        wsUrls: ['ws://x'],
        hostPublicKeyB64: 'pk',
        deviceToken: 't',
      );
      final settings = InMemoryPairingSettingsRepository(
        pairedDesktops: const [desktop],
      );
      final cubit = PairingClientCubit(settings: settings);
      addTearDown(cubit.close);
      await cubit.loadPairedDesktops();

      await cubit.removeDesktop('d1');
      expect(await settings.loadPairedDesktops(), isEmpty);

      await cubit.restoreDesktop(desktop);
      await cubit.restoreDesktop(desktop);

      expect(cubit.state.pairedDesktops, hasLength(1));
      expect((await settings.loadPairedDesktops()).single.id, 'd1');
    });

    test('openSession enters mirroring; input/resize forward to the client',
        () async {
      final fake = _FakePairingClient();
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);

      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();
      await cubit.openSession('ws:p1');

      expect(cubit.state.phase, PairingClientPhase.mirroring);
      expect(cubit.state.activeCatalogId, 'ws:p1');
      expect(cubit.activeSubscription, isNotNull);

      cubit.sendInput([104, 105]);
      cubit.sendResize(120, 40);
      expect(fake.sentInput.single.$1, 42);
      expect(fake.sentInput.single.$2, Uint8List.fromList([104, 105]));
      expect(fake.sentResize.single, (42, 120, 40));
    });

    test('leaveMirror unsubscribes and returns to connected', () async {
      final fake = _FakePairingClient();
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);

      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();
      await cubit.openSession('ws:p1');
      cubit.leaveMirror();

      expect(cubit.state.phase, PairingClientPhase.connected);
      expect(cubit.state.activeCatalogId, isNull);
      expect(cubit.activeSubscription, isNull);
      expect(fake.unsubscribed, [42]);
    });

    test('cancel disposes the client and returns to idle', () async {
      final fake = _FakePairingClient();
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);

      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();
      await cubit.cancel();

      expect(cubit.state.phase, PairingClientPhase.idle);
      expect(cubit.state.pendingOffer, isNull);
      expect(fake.closed, isTrue);
    });

    test('activateAndOpen: live node mirrors directly (no activate)', () async {
      final fake = _FakePairingClient();
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);
      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();

      await cubit.activateAndOpen(
        const PairingSessionNode(
          workspaceId: 'wsA',
          title: 'shell',
          subtitle: '',
          live: true,
          paneId: 'p1',
          catalogId: 'ws:p1',
        ),
      );

      expect(cubit.state.phase, PairingClientPhase.mirroring);
      expect(cubit.state.activeCatalogId, 'ws:p1');
      expect(cubit.state.activatingKey, isNull);
    });

    test('activateAndOpen: dormant node activates then mirrors', () async {
      final fake = _FakePairingClient(
        activateResult: const PairingActivateResult(
          catalogId: 'ws:p2',
          cols: 80,
          rows: 24,
        ),
      );
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);
      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();

      final keys = expectLater(
        cubit.stream.map((s) => s.activatingKey),
        emitsThrough('ws:p2'),
      );
      await cubit.activateAndOpen(
        const PairingSessionNode(
          workspaceId: 'wsA',
          title: 'dead',
          subtitle: '',
          live: false,
          paneId: 'p2',
        ),
      );
      await keys;

      expect(cubit.state.phase, PairingClientPhase.mirroring);
      expect(cubit.state.activeCatalogId, 'ws:p2');
      expect(cubit.state.activatingKey, isNull);
    });

    test('activateAndOpen: failure clears the spinner and raises a notice',
        () async {
      final fake = _FakePairingClient(activateError: Exception('boom'));
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);
      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();

      await cubit.activateAndOpen(
        const PairingSessionNode(
          workspaceId: 'wsA',
          title: 'dead',
          subtitle: '',
          live: false,
          paneId: 'p2',
        ),
      );

      expect(cubit.state.phase, PairingClientPhase.connected);
      expect(cubit.state.activatingKey, isNull);
      expect(cubit.state.notice, PairingNotice.activateFailed);
      cubit.clearNotice();
      expect(cubit.state.notice, isNull);
    });

    test('activateAndOpen: host fallback raises a fallback notice', () async {
      final fake = _FakePairingClient(
        activateResult: const PairingActivateResult(
          catalogId: 'ws:p9',
          cols: 80,
          rows: 24,
          fallback: true,
        ),
      );
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);
      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();

      await cubit.activateAndOpen(
        const PairingSessionNode(
          workspaceId: 'wsA',
          title: 'dead',
          subtitle: '',
          live: false,
          paneId: 'p2',
        ),
      );

      expect(cubit.state.phase, PairingClientPhase.mirroring);
      expect(cubit.state.notice, PairingNotice.fallbackOpenedTerminal);
    });

    test('sessionsChanged from the host refreshes the workspace tree',
        () async {
      final fake = _FakePairingClient();
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);
      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();
      expect(fake.listWorkspacesCalls, 1);

      fake.workspaces = [_wsNode()];
      fake.pushSessionsChanged();
      await Future<void>.delayed(Duration.zero);

      expect(fake.listWorkspacesCalls, 2);
      expect(cubit.state.workspaces, hasLength(1));
    });

    test('removeDesktop drops it from state and storage', () async {
      final settings = InMemoryPairingSettingsRepository(
        pairedDesktops: const [
          PairedDesktop(
            id: 'd1',
            name: 'Home',
            wsUrls: ['ws://x'],
            hostPublicKeyB64: 'pk',
            deviceToken: 't',
          ),
        ],
      );
      final cubit = PairingClientCubit(settings: settings);
      addTearDown(cubit.close);
      await cubit.loadPairedDesktops();
      await cubit.removeDesktop('d1');
      expect(cubit.state.pairedDesktops, isEmpty);
      expect(await settings.loadPairedDesktops(), isEmpty);
    });

    test('uploadImage without an active mirror throws no_target', () async {
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: _FakePairingClient.new,
      );
      addTearDown(cubit.close);

      expect(
        () => cubit.uploadImage(
          filename: 'photo.png',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(
          isA<PairingUploadException>().having(
            (e) => e.code,
            'code',
            'no_target',
          ),
        ),
      );
    });

    test('uploadImage forwards sub, filename, and bytes to the client',
        () async {
      final fake = _FakePairingClient()..uploadPath = '/host/wd/photo.png';
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);

      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();
      await cubit.openSession('ws:p1');

      final bytes = Uint8List.fromList([9, 8, 7]);
      final path = await cubit.uploadImage(filename: 'photo.png', bytes: bytes);

      expect(path, '/host/wd/photo.png');
      expect(fake.uploads.single.$1, 42);
      expect(fake.uploads.single.$2, 'photo.png');
      expect(fake.uploads.single.$3, bytes);
    });
  });
}
