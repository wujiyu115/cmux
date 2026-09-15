import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/quick_open/top_scored.dart';

/// Reference implementation: full sort with the same ordering, then take N.
List<String> referenceTop(List<(int, String)> items, int n) {
  final sorted = [...items]..sort((a, b) {
    if (a.$1 != b.$1) return b.$1.compareTo(a.$1);
    if (a.$2.length != b.$2.length) {
      return a.$2.length.compareTo(b.$2.length);
    }
    return a.$2.compareTo(b.$2);
  });
  return [for (final (_, label) in sorted.take(n)) label];
}

void main() {
  test('keeps the N best candidates, best first', () {
    final top = TopScored<String>(capacity: 3);
    top.add('a', 1, 'a');
    top.add('b', 5, 'b');
    top.add('c', 2, 'c');
    top.add('d', 9, 'd');

    expect(top.toSortedList(), ['d', 'b', 'c']);
  });

  test('fewer candidates than the capacity are all kept, sorted', () {
    final top = TopScored<String>(capacity: 5);
    top.add('b', 5, 'b');
    top.add('a', 1, 'a');
    top.add('c', 3, 'c');

    expect(top.toSortedList(), ['b', 'c', 'a']);
  });

  test('ties: shorter label first, then lexicographic', () {
    final top = TopScored<String>(capacity: 3);
    top.add('bbbb', 7, 'bbbb');
    top.add('aaa', 7, 'aaa');
    top.add('aab', 7, 'aab');
    top.add('zz', 7, 'zz');

    expect(top.toSortedList(), ['zz', 'aaa', 'aab']);
  });

  test('wouldAccept gates candidates below the kept set', () {
    final top = TopScored<String>(capacity: 2);
    top.add('b', 5, 'b');
    top.add('c', 3, 'c');

    expect(top.wouldAccept(2, 'a'), isFalse); // below the worst kept score
    expect(top.wouldAccept(4, 'a'), isTrue); // beats the worst kept (3)
    expect(top.wouldAccept(3, 'a'), isTrue); // ties score, shorter label wins

    top.add('a', 6, 'a');
    expect(top.toSortedList(), ['a', 'b']);
  });

  test('wouldAccept is always true while below capacity', () {
    final top = TopScored<String>(capacity: 2);
    expect(top.wouldAccept(-100, 'a'), isTrue);
    expect(top.isEmpty, isTrue);
  });

  test('matches a reference sort on shuffled input (wouldAccept + add)', () {
    final rng = Random(42);
    for (var trial = 0; trial < 100; trial++) {
      final capacity = 1 + rng.nextInt(9);
      final items = [
        for (var i = 0; i < 200; i++) (rng.nextInt(25), 'f$i'),
      ];
      final top = TopScored<String>(capacity: capacity);
      for (final (score, label) in items) {
        if (!top.wouldAccept(score, label)) continue;
        top.add(label, score, label);
      }
      expect(
        top.toSortedList(),
        referenceTop(items, capacity),
        reason: 'trial $trial, capacity $capacity',
      );
    }
  });

  test('accepting without adding never corrupts the heap', () {
    final top = TopScored<String>(capacity: 2);
    top.add('b', 5, 'b');
    top.add('c', 3, 'c');
    // A wouldAccept-true candidate that is never added is simply dropped.
    expect(top.wouldAccept(9, 'a'), isTrue);
    expect(top.toSortedList(), ['b', 'c']);
  });
}
