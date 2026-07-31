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

const _pane = PairingSessionNode(
  workspaceId: 'wsA',
  title: 'build',
  subtitle: '/home/dev/app',
  live: true,
  paneId: 'p1',
  catalogId: 'ws:p1',
  cols: 120,
  rows: 40,
);
const _secondPane = PairingSessionNode(
  workspaceId: 'wsA',
  title: 'zsh',
  subtitle: '/home/dev/app',
  live: true,
  paneId: 'p2',
  catalogId: 'ws:p2',
  cols: 80,
  rows: 24,
);

const _wsA = PairingWorkspaceNode(
  workspaceId: 'wsA',
  title: 'Workspace A',
  panes: [_pane, _secondPane],
);

const _dormant = PairingWorkspaceNode(
  workspaceId: 'wsB',
  title: 'Dormant',
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

  testWidgets('workspace renders its live terminals with geometry badges',
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
    // The group starts open because the workspace has live panes.
    expect(find.text('build'), findsOneWidget);
    expect(find.text('120×40'), findsOneWidget);
    expect(find.text('zsh'), findsOneWidget);
    expect(find.text('80×24'), findsOneWidget);
    expect(find.text('Live'), findsWidgets);
    expect(find.byKey(AppKeys.pairingSessionNode('ws:p2')), findsOneWidget);

    // Collapsing drops the node rows.
    await tester.tap(find.byKey(AppKeys.pairingWorkspaceHeader('wsA')));
    await tester.pumpAndSettle();

    expect(find.text('build'), findsNothing);
    expect(find.byKey(AppKeys.pairingSessionNode('ws:p2')), findsNothing);
  });

  testWidgets('a workspace with nothing running offers to open a terminal',
      (tester) async {
    cubit.set(
      const PairingClientState(
        phase: PairingClientPhase.connected,
        activeHostName: 'Studio',
        workspaces: [_dormant],
      ),
    );
    await pump(tester);

    // Dormant workspaces start collapsed; open it to reach the action.
    await tester.tap(find.byKey(AppKeys.pairingWorkspaceHeader('wsB')));
    await tester.pumpAndSettle();

    expect(find.text('Open a terminal here'), findsOneWidget);
    await tester.tap(find.byKey(AppKeys.pairingOpenTerminalButton('wsB')));
    await tester.pump();

    // No pane to reuse, so the host is asked to open one for this workspace.
    expect(cubit.activated.single.workspaceId, 'wsB');
    expect(cubit.activated.single.paneId, isNull);
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
