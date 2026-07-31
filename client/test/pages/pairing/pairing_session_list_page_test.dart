import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/pairing_client_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/repositories/pairing_settings_repository.dart';
import 'package:teampilot/pages/pairing/pairing_session_list_page.dart';
import 'package:teampilot/services/pairing/pairing_client.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

class _TestCubit extends PairingClientCubit {
  _TestCubit() : super(settings: InMemoryPairingSettingsRepository());
  void set(PairingClientState s) => emit(s);

  final List<PairingSessionNode> activated = [];
  @override
  Future<void> activateAndOpen(PairingSessionNode node) async {
    activated.add(node);
  }
}

const _liveChat = PairingSessionNode(
  workspaceId: 'wsA',
  kind: 'chat',
  title: 'claude shell',
  subtitle: 'zsh',
  live: true,
  sessionId: 's1',
  catalogId: 'chat:s1:main',
  cols: 80,
  rows: 24,
);
const _deadChat = PairingSessionNode(
  workspaceId: 'wsA',
  kind: 'chat',
  title: 'old shell',
  subtitle: 'bash',
  live: false,
  sessionId: 's2',
);
const _pane = PairingSessionNode(
  workspaceId: 'wsA',
  kind: 'workspace',
  title: 'build',
  subtitle: '',
  live: true,
  paneId: 'p1',
  catalogId: 'ws:p1',
  cols: 120,
  rows: 40,
);

const _wsA = PairingWorkspaceNode(
  workspaceId: 'wsA',
  title: 'Workspace A',
  sessions: [_liveChat, _deadChat],
  panes: [_pane],
);

void main() {
  late _TestCubit cubit;

  setUp(() => cubit = _TestCubit());
  tearDown(() => cubit.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<PairingClientCubit>.value(
          value: cubit,
          child: const PairingSessionListPage(),
        ),
      ),
    );
  }

  testWidgets('empty tree shows the no-workspaces notice', (tester) async {
    cubit.set(
      const PairingClientState(
        phase: PairingClientPhase.connected,
        activeHostName: 'Desk',
      ),
    );
    await pump(tester);

    expect(find.byKey(AppKeys.pairingSessionListPage), findsOneWidget);
    expect(find.text('No workspaces on this desktop.'), findsOneWidget);
  });

  testWidgets('workspace renders sessions + panes with liveness badges',
      (tester) async {
    cubit.set(
      const PairingClientState(
        phase: PairingClientPhase.connected,
        activeHostName: 'Studio',
        workspaces: [_wsA],
      ),
    );
    await pump(tester);

    expect(find.text('Studio'), findsOneWidget);
    expect(find.byKey(AppKeys.pairingWorkspaceHeader('wsA')), findsOneWidget);
    // The group starts open because the workspace has live panes, so both the
    // sessions and the live-terminals sections are on screen.
    expect(find.text('build'), findsOneWidget);
    expect(find.text('120×40'), findsOneWidget);
    expect(find.text('Live'), findsWidgets);
    expect(find.text('claude shell'), findsOneWidget);
    expect(find.text('old shell'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.byKey(AppKeys.pairingSessionNode('chat:s2')), findsOneWidget);

    // Collapsing drops the node rows.
    await tester.tap(find.byKey(AppKeys.pairingWorkspaceHeader('wsA')));
    await tester.pumpAndSettle();

    expect(find.text('claude shell'), findsNothing);
    expect(find.byKey(AppKeys.pairingSessionNode('chat:s2')), findsNothing);
  });

  testWidgets('the connection row shows the URL that actually connected',
      (tester) async {
    cubit.set(
      const PairingClientState(
        phase: PairingClientPhase.connected,
        activeHostName: 'Studio',
        activeHostUrl: 'ws://192.168.1.9:47821/pair/ws',
      ),
    );
    await pump(tester);

    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('ws://192.168.1.9:47821/pair/ws'), findsOneWidget);
  });

  testWidgets('tapping a node calls activateAndOpen', (tester) async {
    cubit.set(
      const PairingClientState(
        phase: PairingClientPhase.connected,
        workspaces: [_wsA],
      ),
    );
    await pump(tester);

    await tester.tap(find.byKey(AppKeys.pairingSessionNode('ws:p1')));
    await tester.pump();

    expect(cubit.activated.single.paneId, 'p1');
  });

  testWidgets('activating node shows a row spinner', (tester) async {
    cubit.set(
      const PairingClientState(
        phase: PairingClientPhase.connected,
        workspaces: [_wsA],
        activatingKey: 'ws:p1',
      ),
    );
    await pump(tester);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('the back button cancels the flow', (tester) async {
    cubit.set(const PairingClientState(phase: PairingClientPhase.connected));
    await pump(tester);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();

    expect(cubit.state.phase, PairingClientPhase.idle);
  });
}
