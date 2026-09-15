/// Bounded top-N accumulator for ranked scans over large candidate sets:
/// keeps only the N best candidates — score descending, then shorter sort
/// label, then label order (quick-open's result ordering) — without
/// collecting or sorting every match. Once full, most offers cost a single
/// comparison against the current worst; accepted replacements sift a heap
/// of N.
///
/// Check [wouldAccept] before building an expensive payload: rejected
/// candidates then cost nothing beyond the score itself.
class TopScored<T> {
  TopScored({required int capacity})
    : assert(capacity > 0, 'capacity must be positive'),
      _capacity = capacity,
      _heap = List<_TopNode<T>?>.filled(capacity, null);

  final int _capacity;
  final List<_TopNode<T>?> _heap;
  var _size = 0;

  bool get isEmpty => _size == 0;

  /// Whether a (score, sortLabel) pair is good enough to enter the top-N.
  /// A `true` result should be followed by [add], otherwise the candidate is
  /// simply dropped.
  bool wouldAccept(int score, String sortLabel) {
    if (_size < _capacity) return true;
    final root = _heap[0]!;
    if (score < root.score) return false;
    return _compareBestFirst(score, sortLabel, root.score, root.sortLabel) < 0;
  }

  /// Offers a candidate; ignored when it does not beat the kept set.
  void add(T value, int score, String sortLabel) {
    if (_size < _capacity) {
      final index = _size++;
      _heap[index] = _TopNode(value, score, sortLabel);
      _siftUp(index);
      return;
    }
    final root = _heap[0]!;
    if (_compareBestFirst(score, sortLabel, root.score, root.sortLabel) >= 0) {
      return;
    }
    _heap[0] = _TopNode(value, score, sortLabel);
    _siftDown(0);
  }

  /// The kept candidates, best first.
  List<T> toSortedList() {
    final nodes = [
      for (var i = 0; i < _size; i++) _heap[i]!,
    ];
    nodes.sort(
      (a, b) => _compareBestFirst(a.score, a.sortLabel, b.score, b.sortLabel),
    );
    return [for (final node in nodes) node.value];
  }

  /// Final display order: higher score first, then shorter label, then label.
  static int _compareBestFirst(
    int aScore,
    String aLabel,
    int bScore,
    String bLabel,
  ) {
    if (aScore != bScore) return bScore.compareTo(aScore);
    final aLen = aLabel.length;
    final bLen = bLabel.length;
    if (aLen != bLen) return aLen.compareTo(bLen);
    return aLabel.compareTo(bLabel);
  }

  /// Min-heap by quality — the root is the worst kept candidate — so a node
  /// may move up only while it is worse than its parent.
  void _siftUp(int index) {
    var i = index;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      final node = _heap[i]!;
      final parentNode = _heap[parent]!;
      if (_compareBestFirst(
            node.score,
            node.sortLabel,
            parentNode.score,
            parentNode.sortLabel,
          ) <=
          0) {
        break;
      }
      _heap[i] = parentNode;
      _heap[parent] = node;
      i = parent;
    }
  }

  /// Pushes a too-good node down until both children are worse-or-equal.
  void _siftDown(int index) {
    var i = index;
    while (true) {
      final left = 2 * i + 1;
      if (left >= _size) break;
      var worst = left;
      final right = left + 1;
      if (right < _size) {
        final leftNode = _heap[left]!;
        final rightNode = _heap[right]!;
        if (_compareBestFirst(
              leftNode.score,
              leftNode.sortLabel,
              rightNode.score,
              rightNode.sortLabel,
            ) <
            0) {
          worst = right;
        }
      }
      final node = _heap[i]!;
      final worstNode = _heap[worst]!;
      if (_compareBestFirst(
            node.score,
            node.sortLabel,
            worstNode.score,
            worstNode.sortLabel,
          ) >=
          0) {
        break;
      }
      _heap[i] = worstNode;
      _heap[worst] = node;
      i = worst;
    }
  }
}

class _TopNode<T> {
  const _TopNode(this.value, this.score, this.sortLabel);

  final T value;
  final int score;
  final String sortLabel;
}
