import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/pairing/recent_pty_buffer.dart';

Uint8List _bytes(int value, int count) =>
    Uint8List.fromList(List<int>.filled(count, value));

void main() {
  group('RecentPtyBuffer', () {
    test('snapshot returns everything appended below the cap', () {
      final buffer = RecentPtyBuffer(maxBytes: 1024);
      buffer.append(_bytes(1, 10));
      buffer.append(_bytes(2, 20));
      final snap = buffer.snapshot();
      expect(snap.bytes.length, 30);
      expect(snap.seq, 30);
    });

    test('seq counts total bytes ever appended, even after eviction', () {
      final buffer = RecentPtyBuffer(maxBytes: 100);
      buffer.append(_bytes(1, 80));
      buffer.append(_bytes(2, 80)); // evicts the first chunk
      expect(buffer.seq, 160);
      final snap = buffer.snapshot();
      // Oldest chunk evicted; only the last 80-byte chunk retained.
      expect(snap.bytes.length, 80);
      expect(snap.bytes.every((b) => b == 2), isTrue);
      expect(snap.seq, 160);
    });

    test('always keeps at least one chunk even when it exceeds the cap', () {
      final buffer = RecentPtyBuffer(maxBytes: 10);
      buffer.append(_bytes(9, 5000));
      final snap = buffer.snapshot();
      expect(snap.bytes.length, 5000);
      expect(snap.seq, 5000);
    });

    test('empty appends are ignored', () {
      final buffer = RecentPtyBuffer();
      buffer.append(Uint8List(0));
      expect(buffer.seq, 0);
      expect(buffer.snapshot().bytes, isEmpty);
    });

    test('clear drops retained bytes but keeps seq monotonic', () {
      final buffer = RecentPtyBuffer();
      buffer.append(_bytes(1, 40));
      buffer.clear();
      expect(buffer.snapshot().bytes, isEmpty);
      expect(buffer.seq, 40);
      buffer.append(_bytes(2, 10));
      expect(buffer.seq, 50);
    });
  });
}
