import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/pairing_client_cubit.dart';
import 'package:teampilot/pages/pairing/pairing_mobile_shell.dart';
import 'package:teampilot/repositories/pairing_settings_repository.dart';

/// Cubit that lets the test freeze any phase without a real socket.
class _TestCubit extends PairingClientCubit {
  _TestCubit() : super(settings: InMemoryPairingSettingsRepository());
  void set(PairingClientState s) => emit(s);
}

void main() {
  late _TestCubit cubit;

  setUp(() => cubit = _TestCubit());
  tearDown(() => cubit.close());

  Future<void> pump(WidgetTester tester, {Widget? child}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<PairingClientCubit>.value(
          value: cubit,
          child: PairingBackLadder(
            state: cubit.state,
            child: child ?? const Scaffold(body: SizedBox.shrink()),
          ),
        ),
      ),
    );
  }

  /// One Android hardware back press. `maybePop` reports true for a press a
  /// [PopScope] swallowed as well as for a real pop, so the assertions below are
  /// on the state the press produced, not on its return value.
  Future<void> back(WidgetTester tester) async {
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pump();
  }

  testWidgets('connected: back leaves the desktop instead of the app', (
    tester,
  ) async {
    cubit.set(
      const PairingClientState(
        phase: PairingClientPhase.connected,
        activeCatalogId: null,
      ),
    );
    await pump(tester);

    await back(tester);
    expect(cubit.state.phase, PairingClientPhase.idle);
  });

  testWidgets('mirroring: back is left to the mirror pane alone', (
    tester,
  ) async {
    cubit.set(
      const PairingClientState(
        phase: PairingClientPhase.mirroring,
        activeCatalogId: 'ws:pane-1',
      ),
    );
    var mirrorClosed = 0;
    await pump(
      tester,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) mirrorClosed++;
        },
        child: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    await back(tester);
    expect(mirrorClosed, 1);
    // The ladder must not also drop the connection: one press, one level.
    expect(cubit.state.phase, PairingClientPhase.mirroring);
  });

  testWidgets('idle: back is not intercepted, so Android can exit', (
    tester,
  ) async {
    cubit.set(const PairingClientState(phase: PairingClientPhase.idle));
    await pump(tester);

    // `find.byType` cannot name a generic widget's runtime type; a predicate can.
    final scope =
        tester.widgetList(find.byWidgetPredicate((w) => w is PopScope)).single
            as PopScope<Object?>;
    expect(
      scope.canPop,
      isTrue,
      reason: 'the hosts list is the root surface; the app may exit from it',
    );
    await back(tester);
    expect(cubit.state.phase, PairingClientPhase.idle);
  });

  testWidgets('confirm: back is left to the confirm page', (tester) async {
    cubit.set(
      const PairingClientState(phase: PairingClientPhase.confirmAwaiting),
    );
    await pump(
      tester,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (_, _) {},
        child: const Scaffold(body: SizedBox.shrink()),
      ),
    );

    await back(tester);
    expect(cubit.state.phase, PairingClientPhase.confirmAwaiting);
  });
}
