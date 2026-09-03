import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/pairing_client_cubit.dart';
import 'package:teampilot/repositories/pairing_settings_repository.dart';
import 'package:teampilot/services/pairing/agent_notice_message.dart';
import 'package:teampilot/services/pairing/pairing_client.dart';
import 'package:teampilot/services/pairing/pairing_offer.dart';
import 'package:teampilot/services/pairing/pairing_upload_sender.dart';
import 'package:teampilot/services/pairing/upload_source.dart';

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
  final _agentNoticeCtrl = StreamController<PairingAgentNotice>.broadcast();
  final _disconnectedCtrl = StreamController<void>.broadcast();
  final List<(int, Uint8List)> sentInput = [];
  final List<(int, int, int)> sentResize = [];
  final List<(int, String, Uint8List)> uploads = [];
  String uploadPath = '/home/me/pics/photo.png';
  final List<int> unsubscribed = [];
  int listWorkspacesCalls = 0;
  bool closed = false;

  /// (folderPath, title, groupId, targetId)
  final List<(String, String?, String?, String?)> createdWorkspaces = [];
  final List<String> createdGroups = [];

  /// Sentinel, not null: these distinguish "never called" from "called with
  /// null", and null is the meaningful value for both.
  String? lastBrowsePath = 'unset';
  String? lastBrowseTargetId = 'unset';

  void pushSessionsChanged() => _changedCtrl.add(null);

  void pushAgentNotice(PairingAgentNotice notice) =>
      _agentNoticeCtrl.add(notice);

  /// What the resume probe should report. [pingGate], when set, parks the
  /// probe's answer until the test completes it, so a socket-death event can
  /// be flushed mid-probe.
  bool pingSucceeds = true;
  Completer<bool>? pingGate;
  int pingCalls = 0;

  @override
  Future<bool> ping() async {
    pingCalls++;
    final gate = pingGate;
    if (gate != null) return gate.future;
    return pingSucceeds;
  }

  /// Whether the cubit still holds its agent-notice subscription. The fake's
  /// controller is closed by [close], so "did the cubit cancel?" has to be read
  /// off the listener count rather than by pushing after teardown.
  bool get agentNoticeHasListener => _agentNoticeCtrl.hasListener;

  /// When set, `terminal.subscribe` throws — the host's `no such session` for a
  /// pane that died between the notification and the tap.
  Object? subscribeError;

  @override
  Stream<String> get log => _logCtrl.stream;

  @override
  Stream<PairingStageEvent> get stages => _stageCtrl.stream;

  @override
  Stream<void> get sessionsChanged => _changedCtrl.stream;

  @override
  Stream<PairingAgentNotice> get agentNotices => _agentNoticeCtrl.stream;

  @override
  Stream<void> get disconnected => _disconnectedCtrl.stream;

  /// Simulates the socket dying on its own (unanswered keepalive / FIN).
  void pushDisconnected() => _disconnectedCtrl.add(null);

  bool get disconnectedHasListener => _disconnectedCtrl.hasListener;

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

  /// What `workspace.list` advertises as the desktop's machines. Empty by
  /// default — the shape a desktop that predates machine selection sends.
  List<PairingTarget> targets = const [];

  @override
  Future<PairingWorkspaceListing> listWorkspaces() async {
    listWorkspacesCalls++;
    return PairingWorkspaceListing(
      workspaces: workspaces,
      groups: const [],
      targets: targets,
    );
  }

  @override
  Future<PairingDirListing> browseDir({String? path, String? targetId}) async {
    lastBrowsePath = path;
    lastBrowseTargetId = targetId;
    return const PairingDirListing(
      path: '/home/me',
      parent: '/home',
      dirs: ['a', 'b'],
    );
  }

  @override
  Future<String> createWorkspace({
    required String folderPath,
    String? title,
    String? groupId,
    String? targetId,
  }) async {
    createdWorkspaces.add((folderPath, title, groupId, targetId));
    return 'ws-new';
  }

  /// When set, `group.create` throws this instead of succeeding — how a host
  /// that does not know the method behaves.
  String? createGroupError;

  @override
  Future<String> createGroup(String name) async {
    final failure = createGroupError;
    if (failure != null) throw Exception(failure);
    createdGroups.add(name);
    return 'g-new';
  }

  @override
  Future<PairingActivateResult> activateSession({
    required String workspaceId,
    String? paneId,
  }) async {
    if (activateError != null) throw activateError!;
    return activateResult;
  }

  final List<String> subscribed = [];

  @override
  Future<PairingSubscription> subscribe(String catalogId) async {
    subscribed.add(catalogId);
    if (subscribeError != null) throw subscribeError!;
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
    required UploadSource source,
    void Function(int sent, int total)? onProgress,
  }) async {
    uploads.add((sub, filename, await source.read(source.length)));
    return uploadPath;
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_logCtrl.isClosed) await _logCtrl.close();
    if (!_stageCtrl.isClosed) await _stageCtrl.close();
    if (!_changedCtrl.isClosed) await _changedCtrl.close();
    if (!_agentNoticeCtrl.isClosed) await _agentNoticeCtrl.close();
    if (!_disconnectedCtrl.isClosed) await _disconnectedCtrl.close();
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

    test('browseDir forwards the path and returns the listing', () async {
      final fake = _FakePairingClient();
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);
      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();

      final result = await cubit.browseDir(path: '/home/me');
      expect(fake.lastBrowsePath, '/home/me');
      expect(result.ok, isTrue);
      expect(result.value!.path, '/home/me');
      expect(result.value!.dirs, ['a', 'b']);
      // No machine chosen: the host is left on its default plane.
      expect(fake.lastBrowseTargetId, isNull);
    });

    test('browseDir forwards the chosen machine', () async {
      final fake = _FakePairingClient();
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);
      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();

      await cubit.browseDir(path: '/home/me', targetId: 'wsl:Ubuntu');
      expect(fake.lastBrowseTargetId, 'wsl:Ubuntu');
    });

    test('createGroup forwards the name and refreshes the tree', () async {
      final fake = _FakePairingClient();
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);
      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();
      expect(fake.listWorkspacesCalls, 1);

      final result = await cubit.createGroup('Frontend');
      expect(result.value, 'g-new');
      expect(fake.createdGroups, ['Frontend']);
      // Success re-lists so the desktop's new group shows on the phone.
      expect(fake.listWorkspacesCalls, 2);
    });

    test('createWorkspace forwards fields and refreshes the tree', () async {
      final fake = _FakePairingClient();
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);
      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();
      expect(fake.listWorkspacesCalls, 1);

      final result = await cubit.createWorkspace(
        folderPath: '/repo/app',
        title: 'App',
        groupId: 'g1',
        targetId: 'wsl:Ubuntu',
      );
      expect(result.value, 'ws-new');
      // targetId rides along: it is what binds the workspace to that machine and
      // decides where its terminal opens.
      expect(
        fake.createdWorkspaces.single,
        ('/repo/app', 'App', 'g1', 'wsl:Ubuntu'),
      );
      expect(fake.listWorkspacesCalls, 2);
    });

    test('the host machines land in state', () async {
      final fake = _FakePairingClient()
        ..targets = const [
          PairingTarget(id: 'local', label: 'This device', kind: 'local'),
          PairingTarget(id: 'wsl:Ubuntu', label: 'WSL · Ubuntu', kind: 'wsl'),
        ];
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);
      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();

      expect(cubit.state.targets.map((t) => t.id), [
        'local',
        'wsl:Ubuntu',
      ]);
      expect(cubit.state.targets.last.label, 'WSL · Ubuntu');
    });

    test('a desktop that advertises no machines leaves targets empty', () async {
      // The stale-desktop shape: the phone must be able to tell "no choice
      // offered" from "local only", because it hides the picker either way but
      // sends a targetId only when the host asked for one.
      final fake = _FakePairingClient();
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);
      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();

      expect(cubit.state.targets, isEmpty);
    });

    test('a refused create carries the host reason, not a bare failure', () async {
      // The regression this guards: a stale desktop answers `unknown method:
      // group.create`, and that text is the only thing that tells the user to
      // rebuild rather than retry. It used to reach the connection log only,
      // which is unreachable once connected.
      final fake = _FakePairingClient()..createGroupError = 'unknown method';
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);
      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();

      final result = await cubit.createGroup('Frontend');
      expect(result.ok, isFalse);
      expect(result.value, isNull);
      expect(result.error, contains('unknown method'));
    });

    test('creating while disconnected fails without throwing', () async {
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
      );
      addTearDown(cubit.close);

      final result = await cubit.createGroup('Frontend');
      expect(result.ok, isFalse);
      expect(result.error, isNotEmpty);
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

    test('uploadMedia without an active mirror throws no_target', () async {
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: _FakePairingClient.new,
      );
      addTearDown(cubit.close);

      expect(
        () => cubit.uploadMedia(
          filename: 'photo.png',
          source: MemoryUploadSource(Uint8List.fromList([1, 2, 3])),
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

    test('uploadMedia forwards sub, filename, and bytes to the client',
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
      final path = await cubit.uploadMedia(
        filename: 'photo.png',
        source: MemoryUploadSource(bytes),
      );

      expect(path, '/host/wd/photo.png');
      expect(fake.uploads.single.$1, 42);
      expect(fake.uploads.single.$2, 'photo.png');
      expect(fake.uploads.single.$3, bytes);
    });
  });

  group('PairingClientCubit agent notices', () {
    const livePane = PairingSessionNode(
      workspaceId: 'wsA',
      title: 'shell',
      subtitle: '',
      live: true,
      paneId: 'p1',
      catalogId: 'ws:p1',
    );

    _FakePairingClient newFake() =>
        _FakePairingClient(workspaces: [_wsNode(panes: const [livePane])]);

    Future<(PairingClientCubit, _FakePairingClient, List<PairingAgentNotice>)>
    connected({_FakePairingClient? client}) async {
      final fake = client ?? newFake();
      final received = <PairingAgentNotice>[];
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => fake,
        onAgentNotice: received.add,
      );
      addTearDown(cubit.close);
      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();
      return (cubit, fake, received);
    }

    test('a host push reaches the injected sink', () async {
      final (_, fake, received) = await connected();

      fake.pushAgentNotice(
        const PairingAgentNotice(
          kind: PairingAgentNoticeKind.waiting,
          seatId: 'ws:p1',
          catalogId: 'ws:p1',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.kind, PairingAgentNoticeKind.waiting);
      expect(received.single.catalogId, 'ws:p1');
    });

    test('cancel releases the notice subscription', () async {
      final (cubit, fake, _) = await connected();
      expect(fake.agentNoticeHasListener, isTrue);

      await cubit.cancel();

      expect(fake.agentNoticeHasListener, isFalse);
    });

    test('close releases the notice subscription', () async {
      // The two dispose paths are duplicated; a cancel added to only one of them
      // leaves this listening after teardown.
      final (cubit, fake, _) = await connected();
      expect(fake.agentNoticeHasListener, isTrue);

      await cubit.close();

      expect(fake.agentNoticeHasListener, isFalse);
    });

    test('openMirrorFromNotification mirrors a live pane', () async {
      final (cubit, fake, _) = await connected();

      await cubit.openMirrorFromNotification('ws:p1');

      expect(cubit.state.phase, PairingClientPhase.mirroring);
      expect(cubit.state.activeCatalogId, 'ws:p1');
      expect(fake.subscribed, ['ws:p1']);
    });

    test('openMirrorFromNotification is a no-op while idle', () async {
      final fake = newFake();
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () => fake,
      );
      addTearDown(cubit.close);

      await cubit.openMirrorFromNotification('ws:p1');

      expect(cubit.state.phase, PairingClientPhase.idle);
      expect(fake.subscribed, isEmpty);
    });

    test('openMirrorFromNotification retries the tree once, then gives up',
        () async {
      final fake = _FakePairingClient(workspaces: const []);
      final (cubit, _, _) = await connected(client: fake);
      expect(fake.listWorkspacesCalls, 1);

      await cubit.openMirrorFromNotification('ws:gone');

      // One refresh in case the pane list lagged a `session.changed`, then stop.
      expect(fake.listWorkspacesCalls, 2);
      expect(fake.subscribed, isEmpty);
      expect(cubit.state.phase, PairingClientPhase.connected);
    });

    test('openMirrorFromNotification releases the previous mirror', () async {
      const second = PairingSessionNode(
        workspaceId: 'wsA',
        title: 'other',
        subtitle: '',
        live: true,
        paneId: 'p2',
        catalogId: 'ws:p2',
      );
      final fake = _FakePairingClient(
        workspaces: [_wsNode(panes: const [livePane, second])],
      );
      final (cubit, _, _) = await connected(client: fake);
      await cubit.openSession('ws:p1');

      await cubit.openMirrorFromNotification('ws:p2');

      // The old subscription is dropped rather than leaked (openSession alone
      // would overwrite it).
      expect(fake.unsubscribed, [42]);
      expect(cubit.state.activeCatalogId, 'ws:p2');
    });

    test('openMirrorFromNotification ignores the pane already mirrored',
        () async {
      final (cubit, fake, _) = await connected();
      await cubit.openSession('ws:p1');

      await cubit.openMirrorFromNotification('ws:p1');

      expect(fake.subscribed, ['ws:p1']);
      expect(fake.unsubscribed, isEmpty);
    });

    test('openMirrorFromNotification swallows a refused subscribe', () async {
      final fake = newFake()..subscribeError = Exception('no such session');
      final (cubit, _, _) = await connected(client: fake);

      await cubit.openMirrorFromNotification('ws:p1');

      expect(cubit.state.phase, PairingClientPhase.connected);
      expect(
        cubit.state.logs.any((l) => l.contains('Open from notification failed')),
        isTrue,
      );
    });
  });

  group('PairingClientCubit reconnect', () {
    const livePane = PairingSessionNode(
      workspaceId: 'wsA',
      title: 'shell',
      subtitle: '',
      live: true,
      paneId: 'p1',
      catalogId: 'ws:p1',
    );

    late List<_FakePairingClient> clients;

    /// Fresh fake per spawn: a reconnect throws the old client away, and the
    /// previous instance has already closed its controllers.
    PairingClientCubit build({
      List<PairingWorkspaceNode> Function(int spawn)? tree,
    }) {
      clients = [];
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () {
          final fake = _FakePairingClient(
            workspaces:
                tree?.call(clients.length) ??
                [_wsNode(panes: const [livePane])],
          );
          clients.add(fake);
          return fake;
        },
      );
      addTearDown(cubit.close);
      return cubit;
    }

    Future<PairingClientCubit> connected() async {
      final cubit = build();
      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();
      return cubit;
    }

    test('a dropped socket starts reconnecting without leaving the screen',
        () async {
      final cubit = await connected();
      await cubit.openSession('ws:p1');

      clients.last.pushDisconnected();
      await Future<void>.delayed(Duration.zero);

      // The mirror stays up on its last frame; only the flag changes.
      expect(cubit.state.phase, PairingClientPhase.mirroring);
      expect(cubit.state.reconnecting, isTrue);
      expect(cubit.state.notice, PairingNotice.connectionLost);
      // The dead subscription is dropped so input stops pretending to arrive.
      expect(cubit.activeSubscription, isNull);
    });

    test('resume reconnects and rebinds the mirror on a new generation',
        () async {
      final cubit = await connected();
      await cubit.openSession('ws:p1');
      final generationBefore = cubit.state.connectGeneration;

      clients.last.pushDisconnected();
      await Future<void>.delayed(Duration.zero);
      cubit.onAppResumed();
      await Future<void>.delayed(Duration.zero);

      // A death the phone already knows about goes straight to the retry — no
      // probe on a socket that is already known dead.
      expect(clients.first.pingCalls, 0);
      expect(cubit.state.reconnecting, isFalse);
      expect(cubit.state.notice, PairingNotice.reconnected);
      expect(cubit.state.phase, PairingClientPhase.mirroring);
      expect(cubit.state.activeCatalogId, 'ws:p1');
      expect(cubit.activeSubscription, isNotNull);
      // The widget key includes this, so the mirror page remounts onto the new
      // subscription instead of listening to the dead one.
      expect(cubit.state.connectGeneration, greaterThan(generationBefore));
      expect(clients, hasLength(2));
      expect(clients.last.subscribed, ['ws:p1']);
    });

    test('resume drops to the session list when the pane did not survive',
        () async {
      // Second spawn advertises an empty tree: the pane died while away.
      final cubit = build(
        tree: (spawn) =>
            spawn == 0 ? [_wsNode(panes: const [livePane])] : const [],
      );
      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();
      await cubit.openSession('ws:p1');

      clients.last.pushDisconnected();
      await Future<void>.delayed(Duration.zero);
      cubit.onAppResumed();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, PairingClientPhase.connected);
      expect(cubit.state.activeCatalogId, isNull);
      expect(cubit.state.reconnecting, isFalse);
      expect(clients.last.subscribed, isEmpty);
    });

    test('a reconnect while merely connected refreshes without a mirror',
        () async {
      final cubit = await connected();

      clients.last.pushDisconnected();
      await Future<void>.delayed(Duration.zero);
      cubit.onAppResumed();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, PairingClientPhase.connected);
      expect(cubit.state.reconnecting, isFalse);
      expect(cubit.state.workspaces, hasLength(1));
      expect(clients.last.subscribed, isEmpty);
    });

    test('cancel ends the retry loop for good', () async {
      final cubit = await connected();
      clients.last.pushDisconnected();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.reconnecting, isTrue);

      await cubit.cancel();
      expect(cubit.state.reconnecting, isFalse);
      expect(cubit.state.phase, PairingClientPhase.idle);

      // A later foreground must not resurrect the connection the user dropped.
      cubit.onAppResumed();
      await Future<void>.delayed(Duration.zero);

      expect(clients, hasLength(1));
      expect(cubit.state.phase, PairingClientPhase.idle);
    });

    test('resume probes a healthy connection and keeps it', () async {
      final cubit = await connected();
      await cubit.openSession('ws:p1');
      final generationBefore = cubit.state.connectGeneration;
      final subscriptionBefore = cubit.activeSubscription;

      cubit.onAppResumed();
      await Future<void>.delayed(Duration.zero);

      // The host answered: the connection, the subscription, and the mirror
      // stay exactly as they were — no rebuild, no generation bump.
      expect(clients, hasLength(1));
      expect(clients.last.pingCalls, 1);
      expect(cubit.state.reconnecting, isFalse);
      expect(cubit.state.phase, PairingClientPhase.mirroring);
      expect(cubit.state.connectGeneration, generationBefore);
      expect(cubit.activeSubscription, same(subscriptionBefore));
    });

    test('resume reconnects immediately when the probe hears silence',
        () async {
      final cubit = await connected();
      await cubit.openSession('ws:p1');
      final generationBefore = cubit.state.connectGeneration;
      // The socket died while the process was frozen: no onDone ever arrived,
      // so only the probe's silence betrays it.
      clients.last.pingSucceeds = false;

      cubit.onAppResumed();
      await Future<void>.delayed(Duration.zero);

      expect(clients, hasLength(2));
      expect(cubit.state.reconnecting, isFalse);
      expect(cubit.state.notice, PairingNotice.reconnected);
      expect(cubit.state.phase, PairingClientPhase.mirroring);
      expect(cubit.state.activeCatalogId, 'ws:p1');
      expect(cubit.state.connectGeneration, greaterThan(generationBefore));
      expect(clients.last.subscribed, ['ws:p1']);
    });

    test('a death event flushed mid-probe does not stack a second recovery',
        () async {
      final cubit = await connected();
      await cubit.openSession('ws:p1');
      final gate = Completer<bool>();
      clients.last.pingGate = gate;

      cubit.onAppResumed();
      // The frozen socket's onDone finally flushes while the probe is still
      // waiting. The probe owns the recovery, so this must not log, clear the
      // mirror, or schedule anything on its own.
      clients.last.pushDisconnected();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.reconnecting, isTrue);
      expect(cubit.state.phase, PairingClientPhase.mirroring);
      expect(cubit.activeSubscription, isNotNull);
      expect(
        cubit.state.logs.where((l) => l.contains('Connection lost')),
        isEmpty,
      );

      gate.complete(false);
      await Future<void>.delayed(Duration.zero);

      // Exactly one loss was ever logged — the probe's — and exactly one
      // recovery ran.
      expect(
        cubit.state.logs.where((l) => l.contains('Connection lost')).length,
        1,
      );
      expect(clients, hasLength(2));
      expect(cubit.state.reconnecting, isFalse);
      expect(cubit.state.phase, PairingClientPhase.mirroring);
    });

    test('resume while pairing a new host leaves the in-flight flow alone',
        () async {
      final cubit = await connected();

      // Still wants the old connection (wantsConnection stays true) but is
      // mid-confirm on a new one — a probe would hit the half-open channel and
      // misread it as death.
      cubit.beginPairing(_makeOffer());
      cubit.onAppResumed();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.phase, PairingClientPhase.confirmAwaiting);
      expect(clients, hasLength(1));
      expect(clients.last.pingCalls, 0);
      expect(cubit.state.reconnecting, isFalse);
    });

    test('a second drop while already reconnecting does not stack', () async {
      final cubit = await connected();

      clients.last.pushDisconnected();
      clients.last.pushDisconnected();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.reconnecting, isTrue);
      expect(
        cubit.state.logs.where((l) => l.contains('Connection lost')).length,
        1,
      );
    });

    test('a failed reconnect stays in the reconnecting state', () async {
      // Every spawn after the first refuses, as a desktop that is actually off.
      clients = [];
      final cubit = PairingClientCubit(
        settings: InMemoryPairingSettingsRepository(),
        clientFactory: () {
          final fake = _FakePairingClient(
            workspaces: [_wsNode(panes: const [livePane])],
            connectError: clients.isEmpty ? null : Exception('no route'),
          );
          clients.add(fake);
          return fake;
        },
      );
      addTearDown(cubit.close);
      cubit.beginPairing(_makeOffer());
      await cubit.confirmPairing();

      clients.last.pushDisconnected();
      await Future<void>.delayed(Duration.zero);
      cubit.onAppResumed();
      await Future<void>.delayed(Duration.zero);

      // Still trying — a failed attempt must not land on the error screen, which
      // would make the user re-pair by hand.
      expect(cubit.state.reconnecting, isTrue);
      expect(cubit.state.phase, PairingClientPhase.connected);
      expect(
        cubit.state.logs.any((l) => l.contains('Reconnect failed')),
        isTrue,
      );
    });

    test('close releases the disconnect subscription', () async {
      final cubit = await connected();
      final fake = clients.last;
      expect(fake.disconnectedHasListener, isTrue);

      await cubit.close();

      expect(fake.disconnectedHasListener, isFalse);
    });
  });

  group('PairingClientState.mirroredPaneTitle', () {
    const panes = [
      PairingSessionNode(
        workspaceId: 'wsA',
        title: '编译 release win',
        subtitle: '',
        live: true,
        paneId: 'p1',
        catalogId: 'ws:p1',
      ),
      PairingSessionNode(
        workspaceId: 'wsA',
        title: '',
        subtitle: '',
        live: true,
        paneId: 'p2',
        catalogId: 'ws:p2',
      ),
    ];

    PairingClientState stateFor(String? catalogId) => PairingClientState(
      workspaces: [_wsNode(panes: panes)],
      activeCatalogId: catalogId,
    );

    test('uses the live pane title matching the active catalog id', () {
      expect(stateFor('ws:p1').mirroredPaneTitle, '编译 release win');
    });

    test('falls back to the workspace title for an untitled pane', () {
      expect(stateFor('ws:p2').mirroredPaneTitle, 'Workspace A');
    });

    test('null when nothing is mirrored or the tree lacks the pane', () {
      expect(stateFor(null).mirroredPaneTitle, isNull);
      expect(stateFor('ws:gone').mirroredPaneTitle, isNull);
    });
  });
}
