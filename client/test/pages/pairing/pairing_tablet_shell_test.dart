import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/pairing_client_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/pairing/pairing_session_list_page.dart';
import 'package:teampilot/pages/pairing/pairing_tablet_layout.dart';
import 'package:teampilot/pages/pairing/pairing_tablet_shell.dart';
import 'package:teampilot/repositories/pairing_settings_repository.dart';
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
const _wsA = PairingWorkspaceNode(
  workspaceId: 'wsA',
  title: 'Workspace A',
  panes: [_pane],
);

void main() {
  late _TestCubit cubit;

  setUp(() => cubit = _TestCubit());
  tearDown(() => cubit.close());

  /// Pumps at a logical window size. `devicePixelRatio` is pinned to 1 so the
  /// size below is the logical size every breakpoint reads.
  Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<PairingClientCubit>.value(
          value: cubit,
          child: child,
        ),
      ),
    );
  }

  group('PairingTabletLayout.isTablet', () {
    Future<bool> isTabletAt(WidgetTester tester, Size size) async {
      late bool result;
      await pumpAt(
        tester,
        size,
        Builder(
          builder: (context) {
            result = PairingTabletLayout.isTablet(context);
            return const SizedBox.shrink();
          },
        ),
      );
      return result;
    }

    testWidgets('iPad portrait and landscape are tablets', (tester) async {
      expect(await isTabletAt(tester, const Size(744, 1133)), isTrue);
      expect(await isTabletAt(tester, const Size(1024, 768)), isTrue);
      expect(await isTabletAt(tester, const Size(1366, 1024)), isTrue);
    });

    testWidgets('phones are not — including a phone in landscape, whose width '
        'alone would clear a width-only breakpoint', (tester) async {
      expect(await isTabletAt(tester, const Size(393, 852)), isFalse);
      expect(await isTabletAt(tester, const Size(430, 932)), isFalse);
      // 932 x 430: the case that motivated testing the shortest side.
      expect(await isTabletAt(tester, const Size(932, 430)), isFalse);
    });

    testWidgets('a narrow iPad Split View pane falls back to the phone stack', (
      tester,
    ) async {
      expect(await isTabletAt(tester, const Size(507, 1024)), isFalse);
    });
  });

  group('PairingTabletShell', () {
    testWidgets('shows the workspace sidebar beside the empty mirror pane', (
      tester,
    ) async {
      cubit.set(
        const PairingClientState(
          phase: PairingClientPhase.connected,
          activeHostName: 'Studio',
          workspaces: [_wsA],
        ),
      );
      await pumpAt(
        tester,
        const Size(1024, 768),
        PairingTabletShell(state: cubit.state),
      );

      expect(find.byKey(AppKeys.pairingTabletShell), findsOneWidget);
      expect(find.byKey(AppKeys.pairingSessionListPage), findsOneWidget);
      expect(find.byKey(AppKeys.pairingNoMirrorPlaceholder), findsOneWidget);
      expect(find.text('No terminal open'), findsOneWidget);
      // The sidebar keeps the phone page's tree and its controls.
      expect(find.text('Studio'), findsOneWidget);
      expect(find.byKey(AppKeys.pairingWorkspaceHeader('wsA')), findsOneWidget);
      expect(find.byKey(AppKeys.pairingWorkspaceSearchField), findsOneWidget);
    });

    testWidgets('a tap in the sidebar opens the terminal instead of swapping '
        'the list away', (tester) async {
      cubit.set(
        const PairingClientState(
          phase: PairingClientPhase.connected,
          activeHostName: 'Studio',
          workspaces: [_wsA],
        ),
      );
      await pumpAt(
        tester,
        const Size(1024, 768),
        PairingTabletShell(state: cubit.state),
      );

      await tester.tap(find.byKey(AppKeys.pairingWorkspaceHeader('wsA')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AppKeys.pairingSessionNode('ws:p1')));
      await tester.pump();

      expect(cubit.activated.single.paneId, 'p1');
    });

    testWidgets(
      'the sidebar is 336 wide on a real tablet, and a share of the window when '
      'a pinned shell is squeezed under the breakpoint',
      (tester) async {
        cubit.set(
          const PairingClientState(
            phase: PairingClientPhase.connected,
            activeHostName: 'Studio',
            workspaces: [_wsA],
          ),
        );
        await pumpAt(
          tester,
          const Size(1024, 768),
          PairingTabletShell(state: cubit.state),
        );
        expect(
          tester.getSize(find.byKey(AppKeys.pairingSessionListPage)).width,
          336,
        );

        // The pinned case: the window shrank back under the breakpoint while a
        // mirror was open, so the two panes share it instead of the mirror being
        // re-parented (which would blank its engine).
        await pumpAt(
          tester,
          const Size(560, 800),
          PairingTabletShell(state: cubit.state),
        );
        expect(
          tester.getSize(find.byKey(AppKeys.pairingSessionListPage)).width,
          closeTo(235.2, 0.1),
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('PairingSessionListPage in the sidebar', () {
    testWidgets('expands and highlights the row whose terminal is mirrored '
        'elsewhere', (tester) async {
      cubit.set(
        const PairingClientState(
          phase: PairingClientPhase.connected,
          activeHostName: 'Studio',
          workspaces: [_wsA],
        ),
      );
      await pumpAt(
        tester,
        const Size(1024, 768),
        const PairingSessionListPage(embedded: true),
      );
      // Collapsed on open, as on a phone.
      expect(find.byKey(AppKeys.pairingSessionNode('ws:p1')), findsNothing);

      // The mirror was opened from somewhere else — a forwarded agent notice or
      // a reconnect — so the sidebar has to reveal the row, not hide it.
      cubit.set(
        const PairingClientState(
          phase: PairingClientPhase.mirroring,
          activeHostName: 'Studio',
          workspaces: [_wsA],
          activeCatalogId: 'ws:p1',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(AppKeys.pairingSessionNode('ws:p1')), findsOneWidget);
    });

    testWidgets('the embedded title is the sidebar size, not the page title', (
      tester,
    ) async {
      cubit.set(
        const PairingClientState(
          phase: PairingClientPhase.connected,
          activeHostName: 'Studio',
        ),
      );
      await pumpAt(
        tester,
        const Size(1024, 768),
        const PairingSessionListPage(embedded: true),
      );

      final title = tester.widget<Text>(find.text('Studio'));
      expect(title.style?.fontSize, 22);

      await pumpAt(
        tester,
        const Size(393, 852),
        const PairingSessionListPage(),
      );
      final fullPageTitle = tester.widget<Text>(find.text('Studio'));
      expect(fullPageTitle.style?.fontSize, 30);
    });
  });
}
