import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/terminal_split.dart';
import 'package:teampilot/models/terminal_surface.dart';
import 'package:teampilot/services/terminal/terminal_layout_coordinator.dart';
import 'package:teampilot/widgets/terminal/terminal_pane_keys.dart';
import 'package:teampilot/widgets/terminal/terminal_split_divider.dart';
import 'package:teampilot/widgets/terminal/terminal_split_view.dart';

/// Counts PTY-hold begin/end so drag transactions can be asserted.
class _FakeHold implements PtyResizeHoldTarget {
  int begins = 0;
  int ends = 0;

  @override
  void beginPtyHold() => begins++;

  @override
  void endPtyHold({bool flush = true}) => ends++;
}

void main() {
  TerminalSurface twoLeaf({double ratio = 0.3, String? zoomedPaneId}) =>
      TerminalSurface(
        id: 's',
        name: 's',
        root: SplitBranch(
          axis: SplitAxis.vertical,
          ratio: ratio,
          first: const SplitLeaf('p1'),
          second: const SplitLeaf('p2'),
        ),
        focusedPaneId: 'p1',
        zoomedPaneId: zoomedPaneId,
      );

  // Stub pane: fills its slot, keyed for measurement, with its own tap handler.
  Widget stubPane(String id, {VoidCallback? onTap}) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.expand(
          child: ColoredBox(
            key: ValueKey('pane-$id'),
            color: const Color(0xFF2233FF),
          ),
        ),
      );

  Future<void> pumpSplit(
    WidgetTester tester, {
    required TerminalSurface surface,
    required TerminalPaneKeys paneKeys,
    required TerminalLayoutCoordinator coordinator,
    void Function(TerminalSurface)? onSurfaceChanged,
    void Function(String)? onPaneFocused,
    void Function(String, GlobalKey<TerminalViewState>)? onBuild,
    Map<String, VoidCallback>? paneTaps,
    Size size = const Size(400, 200),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: TerminalSplitView(
                surface: surface,
                paneKeys: paneKeys,
                coordinator: coordinator,
                onSurfaceChanged: onSurfaceChanged ?? (_) {},
                onPaneFocused: onPaneFocused ?? (_) {},
                paneBuilder: (context, paneId, key, isFocused) {
                  onBuild?.call(paneId, key);
                  return stubPane(paneId, onTap: paneTaps?[paneId]);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders both panes with widths reflecting the ratio',
      (tester) async {
    await pumpSplit(
      tester,
      surface: twoLeaf(ratio: 0.3),
      paneKeys: TerminalPaneKeys(),
      coordinator: TerminalLayoutCoordinator(),
    );

    final w1 = tester.getSize(find.byKey(const ValueKey('pane-p1'))).width;
    final w2 = tester.getSize(find.byKey(const ValueKey('pane-p2'))).width;
    // 400 total - 4px divider = 396 shared 300:700.
    expect(w1, closeTo(396 * 0.3, 2));
    expect(w2, closeTo(396 * 0.7, 2));
  });

  testWidgets('divider drag holds PTYs and writes the new ratio once',
      (tester) async {
    final coordinator = TerminalLayoutCoordinator();
    final hold = _FakeHold();
    coordinator.register(hold);
    final changes = <TerminalSurface>[];

    await pumpSplit(
      tester,
      surface: twoLeaf(ratio: 0.3),
      paneKeys: TerminalPaneKeys(),
      coordinator: coordinator,
      onSurfaceChanged: changes.add,
    );

    await tester.drag(find.byType(TerminalSplitDivider), const Offset(40, 0));
    // Drain the divider's double-tap countdown timer started on pointer-down.
    await tester.pump(const Duration(milliseconds: 400));

    expect(hold.begins, 1);
    expect(hold.ends, 1);
    expect(changes, hasLength(1));
    // 0.3 + 40/400 = 0.4
    expect(branchAtPath(changes.single.root, const [])!.ratio, closeTo(0.4, 0.01));
  });

  testWidgets('drag cancel does not write back', (tester) async {
    final changes = <TerminalSurface>[];
    await pumpSplit(
      tester,
      surface: twoLeaf(ratio: 0.3),
      paneKeys: TerminalPaneKeys(),
      coordinator: TerminalLayoutCoordinator(),
      onSurfaceChanged: changes.add,
    );

    // A pan-down that is released without ever crossing the drag threshold
    // fires onPanCancel (not onPanEnd) → the split view must not write back.
    final center = tester.getCenter(find.byType(TerminalSplitDivider));
    final gesture = await tester.startGesture(center);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(changes, isEmpty);
  });

  testWidgets('divider double-tap resets the ratio to 0.5', (tester) async {
    final changes = <TerminalSurface>[];
    await pumpSplit(
      tester,
      surface: twoLeaf(ratio: 0.3),
      paneKeys: TerminalPaneKeys(),
      coordinator: TerminalLayoutCoordinator(),
      onSurfaceChanged: changes.add,
    );

    final finder = find.byType(TerminalSplitDivider);
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(finder);
    await tester.pumpAndSettle();

    expect(changes, hasLength(1));
    expect(branchAtPath(changes.single.root, const [])!.ratio, 0.5);
  });

  testWidgets('pointer-down focuses the pane without swallowing its tap',
      (tester) async {
    final focused = <String>[];
    var stubTapped = false;
    await pumpSplit(
      tester,
      surface: twoLeaf(ratio: 0.3),
      paneKeys: TerminalPaneKeys(),
      coordinator: TerminalLayoutCoordinator(),
      onPaneFocused: focused.add,
      paneTaps: {'p2': () => stubTapped = true},
    );

    await tester.tap(find.byKey(const ValueKey('pane-p2')));
    await tester.pump();

    expect(focused, contains('p2'));
    expect(stubTapped, isTrue);
  });

  testWidgets('zoom keeps the hidden pane mounted but offstage', (tester) async {
    await pumpSplit(
      tester,
      surface: twoLeaf(ratio: 0.3, zoomedPaneId: 'p1'),
      paneKeys: TerminalPaneKeys(),
      coordinator: TerminalLayoutCoordinator(),
    );

    // find.byKey skips offstage subtrees by default; opt in to prove the hidden
    // pane is still mounted (its engine keeps consuming PTY output).
    final hidden = find.byKey(const ValueKey('pane-p2'), skipOffstage: false);
    expect(hidden, findsOneWidget);
    expect(find.byKey(const ValueKey('pane-p1')), findsOneWidget);

    // MaterialApp/Navigator introduce their own (offstage: false) Offstages, so
    // assert some ancestor Offstage of the hidden pane is actually offstage.
    final offstages = tester.widgetList<Offstage>(
      find.ancestor(of: hidden, matching: find.byType(Offstage)),
    );
    expect(offstages.any((o) => o.offstage), isTrue);
  });

  testWidgets('pane keys survive a ratio-change rebuild', (tester) async {
    final paneKeys = TerminalPaneKeys();
    final coordinator = TerminalLayoutCoordinator();
    final seen = <String, GlobalKey<TerminalViewState>>{};

    await pumpSplit(
      tester,
      surface: twoLeaf(ratio: 0.3),
      paneKeys: paneKeys,
      coordinator: coordinator,
      onBuild: (id, key) => seen[id] = key,
    );
    final firstP1 = seen['p1'];
    final firstP2 = seen['p2'];

    await pumpSplit(
      tester,
      surface: twoLeaf(ratio: 0.6),
      paneKeys: paneKeys,
      coordinator: coordinator,
      onBuild: (id, key) => seen[id] = key,
    );

    expect(identical(seen['p1'], firstP1), isTrue);
    expect(identical(seen['p2'], firstP2), isTrue);
  });
}
