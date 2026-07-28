import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/terminal_split.dart';

void main() {
  // Asymmetric 4-leaf tree:
  //        V(0.5)
  //       /      \
  //   H(0.3)      d
  //   /    \
  //  a    V(0.7)
  //       /   \
  //      b     c
  // Pre-order leaves: a, b, c, d
  SplitNode asymmetric() => const SplitBranch(
        axis: SplitAxis.vertical,
        ratio: 0.5,
        first: SplitBranch(
          axis: SplitAxis.horizontal,
          ratio: 0.3,
          first: SplitLeaf('a'),
          second: SplitBranch(
            axis: SplitAxis.vertical,
            ratio: 0.7,
            first: SplitLeaf('b'),
            second: SplitLeaf('c'),
          ),
        ),
        second: SplitLeaf('d'),
      );

  group('splitLeaves', () {
    test('pre-order ordering on asymmetric tree', () {
      expect(splitLeaves(asymmetric()), ['a', 'b', 'c', 'd']);
    });

    test('single leaf', () {
      expect(splitLeaves(const SplitLeaf('x')), ['x']);
    });
  });

  group('splitLeaf', () {
    test('splits a leaf into a branch (first=old, second=new, ratio 0.5)', () {
      final tree = splitLeaf(
        const SplitLeaf('a'),
        'a',
        SplitAxis.horizontal,
        'b',
      );
      expect(
        tree,
        const SplitBranch(
          axis: SplitAxis.horizontal,
          ratio: 0.5,
          first: SplitLeaf('a'),
          second: SplitLeaf('b'),
        ),
      );
    });

    test('splits a nested leaf, leaving the rest untouched', () {
      final tree = splitLeaf(asymmetric(), 'd', SplitAxis.vertical, 'e');
      expect(splitLeaves(tree), ['a', 'b', 'c', 'd', 'e']);
    });

    test('unknown paneId is a no-op returning the same tree', () {
      final root = asymmetric();
      expect(splitLeaf(root, 'zzz', SplitAxis.vertical, 'new'), root);
    });
  });

  group('removePane', () {
    test('sibling collapses into parent at depth >= 2', () {
      // Remove 'b' -> its sibling V(0.7) subtree collapses; but b's direct
      // sibling is 'c', so parent becomes leaf 'c'.
      final tree = removePane(asymmetric(), 'b');
      expect(splitLeaves(tree!), ['a', 'c', 'd']);
      expect(
        tree,
        const SplitBranch(
          axis: SplitAxis.vertical,
          ratio: 0.5,
          first: SplitBranch(
            axis: SplitAxis.horizontal,
            ratio: 0.3,
            first: SplitLeaf('a'),
            second: SplitLeaf('c'),
          ),
          second: SplitLeaf('d'),
        ),
      );
    });

    test('removing a top-level child collapses to sibling subtree', () {
      final tree = removePane(asymmetric(), 'd');
      expect(splitLeaves(tree!), ['a', 'b', 'c']);
      expect(
        tree,
        const SplitBranch(
          axis: SplitAxis.horizontal,
          ratio: 0.3,
          first: SplitLeaf('a'),
          second: SplitBranch(
            axis: SplitAxis.vertical,
            ratio: 0.7,
            first: SplitLeaf('b'),
            second: SplitLeaf('c'),
          ),
        ),
      );
    });

    test('removing the last remaining leaf returns null', () {
      expect(removePane(const SplitLeaf('only'), 'only'), isNull);
    });

    test('unknown paneId returns the tree unchanged', () {
      final root = asymmetric();
      expect(removePane(root, 'zzz'), root);
    });
  });

  group('nextLeaf / prevLeaf', () {
    test('next steps forward with wrap-around', () {
      final root = asymmetric();
      expect(nextLeaf(root, 'a'), 'b');
      expect(nextLeaf(root, 'c'), 'd');
      expect(nextLeaf(root, 'd'), 'a'); // wrap
    });

    test('prev steps backward with wrap-around', () {
      final root = asymmetric();
      expect(prevLeaf(root, 'b'), 'a');
      expect(prevLeaf(root, 'a'), 'd'); // wrap
      expect(prevLeaf(root, 'd'), 'c');
    });

    test('single leaf returns itself both directions', () {
      const root = SplitLeaf('solo');
      expect(nextLeaf(root, 'solo'), 'solo');
      expect(prevLeaf(root, 'solo'), 'solo');
    });

    test('unknown paneId returns null', () {
      final root = asymmetric();
      expect(nextLeaf(root, 'zzz'), isNull);
      expect(prevLeaf(root, 'zzz'), isNull);
    });
  });

  group('equalize', () {
    test('sets every branch ratio to 0.5', () {
      final tree = equalize(asymmetric());
      expect(
        tree,
        const SplitBranch(
          axis: SplitAxis.vertical,
          ratio: 0.5,
          first: SplitBranch(
            axis: SplitAxis.horizontal,
            ratio: 0.5,
            first: SplitLeaf('a'),
            second: SplitBranch(
              axis: SplitAxis.vertical,
              ratio: 0.5,
              first: SplitLeaf('b'),
              second: SplitLeaf('c'),
            ),
          ),
          second: SplitLeaf('d'),
        ),
      );
    });
  });

  group('resizePane', () {
    test('sets the ratio on the leaf\'s parent branch', () {
      // 'd' parents the outer V branch.
      final tree = resizePane(asymmetric(), 'd', 0.42) as SplitBranch;
      expect(tree.ratio, 0.42);
    });

    test('targets the deep parent branch for a nested leaf', () {
      // 'b' parents the inner V(0.7) branch.
      final tree = resizePane(asymmetric(), 'b', 0.25) as SplitBranch;
      final inner = (tree.first as SplitBranch).second as SplitBranch;
      expect(inner.ratio, 0.25);
      // outer + intermediate ratios untouched
      expect(tree.ratio, 0.5);
      expect((tree.first as SplitBranch).ratio, 0.3);
    });

    test('clamps below to 0.1', () {
      final tree = resizePane(asymmetric(), 'd', -5.0) as SplitBranch;
      expect(tree.ratio, 0.1);
    });

    test('clamps above to 0.9', () {
      final tree = resizePane(asymmetric(), 'd', 5.0) as SplitBranch;
      expect(tree.ratio, 0.9);
    });

    test('unknown paneId returns tree unchanged', () {
      final root = asymmetric();
      expect(resizePane(root, 'zzz', 0.3), root);
    });
  });

  group('swapPanes', () {
    test('swaps two leaves in place', () {
      final tree = swapPanes(asymmetric(), 'a', 'd');
      expect(splitLeaves(tree), ['d', 'b', 'c', 'a']);
    });

    test('missing id returns tree unchanged', () {
      final root = asymmetric();
      expect(swapPanes(root, 'a', 'zzz'), root);
    });
  });

  group('containsPane', () {
    test('true for present, false for absent', () {
      final root = asymmetric();
      expect(containsPane(root, 'c'), isTrue);
      expect(containsPane(root, 'zzz'), isFalse);
    });
  });

  group('JSON', () {
    test('round trips a branch tree', () {
      final root = asymmetric();
      final decoded = splitNodeFromJson(splitNodeToJson(root));
      expect(decoded, root);
    });

    test('round trips a single leaf', () {
      const root = SplitLeaf('solo');
      expect(splitNodeFromJson(splitNodeToJson(root)), root);
    });

    test('leaf encodes with defaults', () {
      expect(splitNodeToJson(const SplitLeaf('p')), {
        'isLeaf': true,
        'paneId': 'p',
        'direction': 'Vertical',
        'splitRatio': 0.5,
        'first': null,
        'second': null,
      });
    });

    test('horizontal branch encodes direction', () {
      final json = splitNodeToJson(
        const SplitBranch(
          axis: SplitAxis.horizontal,
          ratio: 0.3,
          first: SplitLeaf('a'),
          second: SplitLeaf('b'),
        ),
      );
      expect(json['direction'], 'Horizontal');
      expect(json['isLeaf'], false);
      expect(json['splitRatio'], 0.3);
    });

    test('garbage decodes to null', () {
      expect(splitNodeFromJson(null), isNull);
      expect(splitNodeFromJson('nope'), isNull);
      expect(splitNodeFromJson(42), isNull);
      expect(splitNodeFromJson(<String, Object?>{}), isNull);
      // isLeaf true but no paneId
      expect(splitNodeFromJson({'isLeaf': true}), isNull);
      // branch missing a child
      expect(
        splitNodeFromJson({
          'isLeaf': false,
          'direction': 'Vertical',
          'splitRatio': 0.5,
          'first': {'isLeaf': true, 'paneId': 'a'},
          'second': null,
        }),
        isNull,
      );
    });
  });

  group('preset builders', () {
    test('buildColumns shape and ratios (equal columns)', () {
      final tree = buildColumns(['a', 'b', 'c']);
      expect(
        tree,
        const SplitBranch(
          axis: SplitAxis.vertical,
          ratio: 2 / 3,
          first: SplitBranch(
            axis: SplitAxis.vertical,
            ratio: 1 / 2,
            first: SplitLeaf('a'),
            second: SplitLeaf('b'),
          ),
          second: SplitLeaf('c'),
        ),
      );
      expect(splitLeaves(tree), ['a', 'b', 'c']);
    });

    test('buildRows uses horizontal axis', () {
      final tree = buildRows(['a', 'b', 'c']);
      expect(
        tree,
        const SplitBranch(
          axis: SplitAxis.horizontal,
          ratio: 2 / 3,
          first: SplitBranch(
            axis: SplitAxis.horizontal,
            ratio: 1 / 2,
            first: SplitLeaf('a'),
            second: SplitLeaf('b'),
          ),
          second: SplitLeaf('c'),
        ),
      );
    });

    test('single id builders return a leaf', () {
      expect(buildColumns(['x']), const SplitLeaf('x'));
      expect(buildRows(['x']), const SplitLeaf('x'));
      expect(buildMainStack(['x']), const SplitLeaf('x'));
    });

    test('empty list throws ArgumentError', () {
      expect(() => buildColumns([]), throwsArgumentError);
      expect(() => buildRows([]), throwsArgumentError);
      expect(() => buildMainStack([]), throwsArgumentError);
    });

    test('buildGrid2x2 is row-major (outer horizontal, inner vertical)', () {
      final tree = buildGrid2x2(['a', 'b', 'c', 'd']);
      expect(
        tree,
        const SplitBranch(
          axis: SplitAxis.horizontal,
          ratio: 0.5,
          first: SplitBranch(
            axis: SplitAxis.vertical,
            ratio: 0.5,
            first: SplitLeaf('a'),
            second: SplitLeaf('b'),
          ),
          second: SplitBranch(
            axis: SplitAxis.vertical,
            ratio: 0.5,
            first: SplitLeaf('c'),
            second: SplitLeaf('d'),
          ),
        ),
      );
      expect(splitLeaves(tree), ['a', 'b', 'c', 'd']);
    });

    test('buildGrid2x2 requires exactly 4 ids', () {
      expect(() => buildGrid2x2(['a', 'b', 'c']), throwsArgumentError);
      expect(
        () => buildGrid2x2(['a', 'b', 'c', 'd', 'e']),
        throwsArgumentError,
      );
    });

    test('buildMainStack: main at 0.6 beside horizontal stack', () {
      final tree = buildMainStack(['main', 's1', 's2']);
      expect(
        tree,
        const SplitBranch(
          axis: SplitAxis.vertical,
          ratio: 0.6,
          first: SplitLeaf('main'),
          second: SplitBranch(
            axis: SplitAxis.horizontal,
            ratio: 1 / 2,
            first: SplitLeaf('s1'),
            second: SplitLeaf('s2'),
          ),
        ),
      );
      expect(splitLeaves(tree), ['main', 's1', 's2']);
    });

    test('buildMainStack with two ids: main + single stacked pane', () {
      final tree = buildMainStack(['main', 's1']);
      expect(
        tree,
        const SplitBranch(
          axis: SplitAxis.vertical,
          ratio: 0.6,
          first: SplitLeaf('main'),
          second: SplitLeaf('s1'),
        ),
      );
    });
  });
}
