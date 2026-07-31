import 'dart:typed_data';

/// A newly-subscribing mirror needs the recent screen state, but the terminal
/// engine exposes no scrollback serialization. This bounded ring keeps the last
/// ~[maxBytes] of raw PTY output per session so a fresh subscriber can be
/// replayed a [snapshot] and then follow live output without a gap.
///
/// [seq] is a monotonically increasing byte counter (total bytes ever appended).
/// Live output frames carry the same running counter, so the client drops any
/// live frame whose `seq` is already covered by the snapshot's high-water mark.
class RecentPtyBuffer {
  RecentPtyBuffer({this.maxBytes = 64 * 1024});

  final int maxBytes;
  final _chunks = <Uint8List>[];
  int _size = 0;
  int _seq = 0;

  /// High-water byte count fed so far (also the snapshot's ending seq).
  int get seq => _seq;

  void append(Uint8List data) {
    if (data.isEmpty) return;
    _chunks.add(data);
    _size += data.length;
    _seq += data.length;
    // Evict oldest chunks past the cap, but always keep at least one so a huge
    // single write is still (partially) replayable.
    while (_size > maxBytes && _chunks.length > 1) {
      _size -= _chunks.removeAt(0).length;
    }
  }

  /// Concatenated recent bytes plus the ending [seq]. Cheap to call; allocates
  /// one contiguous buffer sized to the retained window.
  PtySnapshot snapshot() {
    final out = Uint8List(_size);
    var offset = 0;
    for (final chunk in _chunks) {
      out.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return PtySnapshot(out, _seq);
  }

  void clear() {
    _chunks.clear();
    _size = 0;
    // seq intentionally NOT reset — it must stay monotonic across the session.
  }
}

class PtySnapshot {
  const PtySnapshot(this.bytes, this.seq);
  final Uint8List bytes;
  final int seq;
}
