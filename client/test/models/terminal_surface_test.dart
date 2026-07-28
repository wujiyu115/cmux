import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/terminal_split.dart';
import 'package:teampilot/models/terminal_surface.dart';

void main() {
  // Surface with panes a, b, c (pre-order), focus on 'b'.
  TerminalSurface sample() => TerminalSurface(
        id: 's1',
        name: 'Tab',
        root: const SplitBranch(
          axis: SplitAxis.vertical,
          ratio: 0.5,
          first: SplitLeaf('a'),
          second: SplitBranch(
            axis: SplitAxis.horizontal,
            ratio: 0.5,
            first: SplitLeaf('b'),
            second: SplitLeaf('c'),
          ),
        ),
        focusedPaneId: 'b',
        paneNames: const {'a': 'Left', 'b': 'Editor'},
        zoomedPaneId: 'b',
      );

  group('single', () {
    test('one-leaf surface focused on its pane', () {
      final s = TerminalSurface.single(id: 'x', name: 'One', paneId: 'p');
      expect(s.root, const SplitLeaf('p'));
      expect(s.focusedPaneId, 'p');
      expect(s.paneIds, ['p']);
      expect(s.zoomedPaneId, isNull);
      expect(s.displayNameFor('p'), '');
    });
  });

  group('displayNameFor', () {
    test('custom name or empty string', () {
      final s = sample();
      expect(s.displayNameFor('a'), 'Left');
      expect(s.displayNameFor('c'), '');
    });
  });

  group('copyWith', () {
    test('overrides fields, preserves the rest', () {
      final s = sample();
      final renamed = s.copyWith(name: 'Renamed', focusedPaneId: 'a');
      expect(renamed.name, 'Renamed');
      expect(renamed.focusedPaneId, 'a');
      expect(renamed.id, s.id);
      expect(renamed.root, s.root);
      expect(renamed.zoomedPaneId, 'b');
    });

    test('clearZoom drops the zoomed pane', () {
      final s = sample();
      expect(s.copyWith(clearZoom: true).zoomedPaneId, isNull);
    });
  });

  group('withPaneRemoved', () {
    test('removing the focused pane migrates focus to nearest survivor', () {
      // Remove focused 'b'; pre-order survivors are a, c. Nearest after b is c.
      final next = sample().withPaneRemoved('b');
      expect(next.paneIds, ['a', 'c']);
      expect(next.focusedPaneId, 'c');
      // zoom pointed at removed pane -> cleared
      expect(next.zoomedPaneId, isNull);
    });

    test('removing the last pane in pre-order falls back to previous', () {
      final s = sample().copyWith(focusedPaneId: 'c', clearZoom: true);
      final next = s.withPaneRemoved('c');
      expect(next.paneIds, ['a', 'b']);
      expect(next.focusedPaneId, 'b');
    });

    test('removing a non-focused pane keeps focus and drops its name', () {
      final next = sample().withPaneRemoved('a');
      expect(next.paneIds, ['b', 'c']);
      expect(next.focusedPaneId, 'b');
      expect(next.displayNameFor('a'), '');
      expect(next.paneNames.containsKey('a'), isFalse);
      // zoom still on 'b'
      expect(next.zoomedPaneId, 'b');
    });

    test('removing a non-zoomed pane preserves the zoom', () {
      final next = sample().withPaneRemoved('a');
      expect(next.zoomedPaneId, 'b');
    });

    test('removing the last pane throws StateError', () {
      final s = TerminalSurface.single(id: 'x', name: 'One', paneId: 'p');
      expect(() => s.withPaneRemoved('p'), throwsStateError);
    });
  });

  group('JSON', () {
    test('round trips', () {
      final s = sample();
      final decoded = TerminalSurface.fromJson(s.toJson());
      expect(decoded, s);
    });

    test('round trips a single-pane surface', () {
      final s = TerminalSurface.single(id: 'x', name: 'One', paneId: 'p');
      expect(TerminalSurface.fromJson(s.toJson()), s);
    });

    test('uses C# SurfaceState key names', () {
      final json = sample().toJson();
      expect(json.keys, containsAll(<String>['id', 'name', 'rootNode', 'focusedPaneId', 'paneCustomNames']));
      expect((json['rootNode'] as Map)['isLeaf'], false);
    });

    test('garbage decodes to null', () {
      expect(TerminalSurface.fromJson(null), isNull);
      expect(TerminalSurface.fromJson('nope'), isNull);
      expect(TerminalSurface.fromJson(<String, Object?>{}), isNull);
      // missing rootNode
      expect(TerminalSurface.fromJson({'id': 'x', 'name': 'y'}), isNull);
      // malformed rootNode
      expect(
        TerminalSurface.fromJson({
          'id': 'x',
          'name': 'y',
          'rootNode': {'isLeaf': true},
        }),
        isNull,
      );
    });

    test('repairs a focus that no longer names a leaf', () {
      final json = sample().toJson();
      json['focusedPaneId'] = 'ghost';
      final decoded = TerminalSurface.fromJson(json)!;
      // falls back to the first pre-order leaf
      expect(decoded.focusedPaneId, 'a');
    });
  });

  group('equality', () {
    test('structural equality including pane names', () {
      expect(sample(), sample());
      expect(sample().hashCode, sample().hashCode);
      expect(sample() == sample().copyWith(name: 'Other'), isFalse);
    });
  });
}
