import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/terminal_split.dart';
import 'package:teampilot/models/terminal_surface.dart';
import 'package:teampilot/services/terminal/terminal_layout_presets.dart';

void main() {
  TerminalSurface surfaceOf(
    List<String> ids, {
    String? focus,
    String? zoom,
    Map<String, String> names = const {},
  }) {
    return TerminalSurface(
      id: 'surface',
      name: 'Surface',
      root: buildColumns(ids),
      focusedPaneId: focus ?? ids.first,
      paneNames: names,
      zoomedPaneId: zoom,
    );
  }

  group('presetSlotCount', () {
    test('matches the documented slot counts', () {
      expect(presetSlotCount(TerminalLayoutPreset.single), 1);
      expect(presetSlotCount(TerminalLayoutPreset.columns2), 2);
      expect(presetSlotCount(TerminalLayoutPreset.columns3), 3);
      expect(presetSlotCount(TerminalLayoutPreset.grid2x2), 4);
      expect(presetSlotCount(TerminalLayoutPreset.mainStack), 3);
    });
  });

  test('throws ArgumentError on empty paneIds', () {
    final surface = surfaceOf(['a']);
    expect(
      () => applyLayoutPreset(
        surface,
        TerminalLayoutPreset.columns2,
        paneIds: const [],
      ),
      throwsArgumentError,
    );
  });

  test('throws ArgumentError on duplicate paneIds', () {
    final surface = surfaceOf(['a', 'b']);
    expect(
      () => applyLayoutPreset(
        surface,
        TerminalLayoutPreset.columns2,
        paneIds: const ['a', 'a'],
      ),
      throwsArgumentError,
    );
  });

  // The losslessness guarantee: for every preset and every relationship between
  // pane count and slot count, the output leaves must equal the input id set.
  group('lossless across fewer / exact / more panes', () {
    for (final preset in TerminalLayoutPreset.values) {
      final slots = presetSlotCount(preset);
      final counts = <int>{
        if (slots > 1) slots - 1, // fewer
        slots, // exact
        slots + 2, // more (overflow)
        slots + 3,
      }..removeWhere((n) => n < 1);
      for (final count in counts) {
        test('$preset with $count panes keeps every pane', () {
          final ids = [for (var i = 0; i < count; i++) 'p$i'];
          final result = applyLayoutPreset(
            surfaceOf(ids),
            preset,
            paneIds: ids,
          );
          expect(
            splitLeaves(result.root).toSet(),
            ids.toSet(),
            reason: 'no pane may be dropped',
          );
          // A permutation: same length, no duplicates introduced.
          expect(splitLeaves(result.root), hasLength(count));
        });
      }
    }
  });

  group('exact-case tree shapes', () {
    test('single → a lone leaf', () {
      final result = applyLayoutPreset(
        surfaceOf(['a']),
        TerminalLayoutPreset.single,
        paneIds: ['a'],
      );
      expect(result.root, const SplitLeaf('a'));
    });

    test('columns2 → vertical spine of two', () {
      final result = applyLayoutPreset(
        surfaceOf(['a', 'b']),
        TerminalLayoutPreset.columns2,
        paneIds: ['a', 'b'],
      );
      expect(result.root, buildColumns(['a', 'b']));
    });

    test('columns3 → vertical spine of three', () {
      final result = applyLayoutPreset(
        surfaceOf(['a', 'b', 'c']),
        TerminalLayoutPreset.columns3,
        paneIds: ['a', 'b', 'c'],
      );
      expect(result.root, buildColumns(['a', 'b', 'c']));
    });

    test('grid2x2 → the 2x2 grid', () {
      final result = applyLayoutPreset(
        surfaceOf(['a', 'b', 'c', 'd']),
        TerminalLayoutPreset.grid2x2,
        paneIds: ['a', 'b', 'c', 'd'],
      );
      expect(result.root, buildGrid2x2(['a', 'b', 'c', 'd']));
    });

    test('mainStack → main pane beside the stack', () {
      final result = applyLayoutPreset(
        surfaceOf(['a', 'b', 'c']),
        TerminalLayoutPreset.mainStack,
        paneIds: ['a', 'b', 'c'],
      );
      expect(result.root, buildMainStack(['a', 'b', 'c']));
    });
  });

  group('fewer-than-slots shapes', () {
    test('grid2x2 with 3 ids falls back to main+stack', () {
      final result = applyLayoutPreset(
        surfaceOf(['a', 'b', 'c']),
        TerminalLayoutPreset.grid2x2,
        paneIds: ['a', 'b', 'c'],
      );
      expect(result.root, buildMainStack(['a', 'b', 'c']));
    });

    test('grid2x2 with 2 ids falls back to columns', () {
      final result = applyLayoutPreset(
        surfaceOf(['a', 'b']),
        TerminalLayoutPreset.grid2x2,
        paneIds: ['a', 'b'],
      );
      expect(result.root, buildColumns(['a', 'b']));
    });

    test('columns3 with 2 ids is a narrower spine', () {
      final result = applyLayoutPreset(
        surfaceOf(['a', 'b']),
        TerminalLayoutPreset.columns3,
        paneIds: ['a', 'b'],
      );
      expect(result.root, buildColumns(['a', 'b']));
    });
  });

  group('overflow: stackIntoLast keeps the trailing panes as rows', () {
    test('columns2 with 4 ids stacks the last 3 into the second slot', () {
      final ids = ['a', 'b', 'c', 'd'];
      final result = applyLayoutPreset(
        surfaceOf(ids),
        TerminalLayoutPreset.columns2,
        paneIds: ids,
      );
      final root = result.root as SplitBranch;
      expect(root.axis, SplitAxis.vertical);
      expect(root.first, const SplitLeaf('a'));
      // The overflow tail is a horizontal rows spine over b, c, d.
      expect(splitLeaves(root.second), ['b', 'c', 'd']);
      final tail = root.second as SplitBranch;
      expect(tail.axis, SplitAxis.horizontal);
    });

    test('grid2x2 with 6 ids stacks the last 3 into the bottom-right cell', () {
      final ids = ['a', 'b', 'c', 'd', 'e', 'f'];
      final result = applyLayoutPreset(
        surfaceOf(ids),
        TerminalLayoutPreset.grid2x2,
        paneIds: ids,
      );
      final root = result.root as SplitBranch;
      final rightHalf = root.second as SplitBranch;
      // Bottom-right cell holds d, e, f stacked as rows.
      expect(splitLeaves(rightHalf.second), ['d', 'e', 'f']);
      expect(splitLeaves(result.root).toSet(), ids.toSet());
    });

    test('single with 3 ids stacks them all as rows', () {
      final ids = ['a', 'b', 'c'];
      final result = applyLayoutPreset(
        surfaceOf(ids),
        TerminalLayoutPreset.single,
        paneIds: ids,
      );
      expect(splitLeaves(result.root), ['a', 'b', 'c']);
      final root = result.root as SplitBranch;
      expect(root.axis, SplitAxis.horizontal);
    });
  });

  group('focus and zoom handling', () {
    test('preserves focus when it is still present', () {
      final result = applyLayoutPreset(
        surfaceOf(['a', 'b', 'c'], focus: 'b'),
        TerminalLayoutPreset.columns2,
        paneIds: ['a', 'b', 'c'],
      );
      expect(result.focusedPaneId, 'b');
    });

    test('falls back to first id when focus is gone from paneIds', () {
      // Focus 'c' is not part of the new pane list → becomes the first id.
      final result = applyLayoutPreset(
        surfaceOf(['a', 'b', 'c'], focus: 'c'),
        TerminalLayoutPreset.columns2,
        paneIds: ['a', 'b'],
      );
      expect(result.focusedPaneId, 'a');
    });

    test('keeps zoom when still present', () {
      final result = applyLayoutPreset(
        surfaceOf(['a', 'b'], zoom: 'b'),
        TerminalLayoutPreset.columns2,
        paneIds: ['a', 'b'],
      );
      expect(result.zoomedPaneId, 'b');
    });

    test('clears zoom when the zoomed pane is gone', () {
      final result = applyLayoutPreset(
        surfaceOf(['a', 'b', 'c'], zoom: 'c'),
        TerminalLayoutPreset.columns2,
        paneIds: ['a', 'b'],
      );
      expect(result.zoomedPaneId, isNull);
    });

    test('drops pane names for ids no longer present', () {
      final result = applyLayoutPreset(
        surfaceOf(
          ['a', 'b', 'c'],
          names: {'a': 'Alpha', 'c': 'Gamma'},
        ),
        TerminalLayoutPreset.columns2,
        paneIds: ['a', 'b'],
      );
      expect(result.paneNames, {'a': 'Alpha'});
    });
  });
}
