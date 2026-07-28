/// Immutable binary split-tree algebra for terminal pane layouts.
///
/// Ported from the C# `SplitNode` (Cmux.Core). Every top-level function is
/// pure: it returns a NEW tree and never mutates its input. Pre-order leaf
/// traversal ([splitLeaves]) defines the canonical pane order that navigation,
/// removal, and preset builders all rely on.
library;

import 'dart:ui' show Rect;

/// A split orientation. [vertical] lays children out side-by-side (columns);
/// [horizontal] stacks them top/bottom (rows).
enum SplitAxis { vertical, horizontal }

/// JSON object alias for encode/decode helpers.
typedef JsonMap = Map<String, Object?>;

/// A node in the split tree: either a [SplitLeaf] pane or a [SplitBranch].
sealed class SplitNode {
  const SplitNode();
}

/// A terminal pane, identified by [paneId].
final class SplitLeaf extends SplitNode {
  const SplitLeaf(this.paneId);

  final String paneId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SplitLeaf && other.paneId == paneId);

  @override
  int get hashCode => paneId.hashCode;

  @override
  String toString() => 'SplitLeaf($paneId)';
}

/// A container splitting [first] and [second] along [axis]. [ratio] is the
/// fraction of space given to [first] (0..1).
final class SplitBranch extends SplitNode {
  const SplitBranch({
    required this.axis,
    required this.ratio,
    required this.first,
    required this.second,
  });

  final SplitAxis axis;
  final double ratio;
  final SplitNode first;
  final SplitNode second;

  SplitBranch copyWith({
    SplitAxis? axis,
    double? ratio,
    SplitNode? first,
    SplitNode? second,
  }) {
    return SplitBranch(
      axis: axis ?? this.axis,
      ratio: ratio ?? this.ratio,
      first: first ?? this.first,
      second: second ?? this.second,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SplitBranch &&
          other.axis == axis &&
          other.ratio == ratio &&
          other.first == first &&
          other.second == second);

  @override
  int get hashCode => Object.hash(axis, ratio, first, second);

  @override
  String toString() => 'SplitBranch($axis, $ratio, $first, $second)';
}

/// Pre-order leaf pane ids. This ordering IS the pane order.
List<String> splitLeaves(SplitNode root) {
  final out = <String>[];
  void walk(SplitNode n) {
    if (n is SplitLeaf) {
      out.add(n.paneId);
      return;
    }
    final b = n as SplitBranch;
    walk(b.first);
    walk(b.second);
  }

  walk(root);
  return out;
}

/// True if [paneId] is a leaf anywhere in [root].
bool containsPane(SplitNode root, String paneId) {
  if (root is SplitLeaf) return root.paneId == paneId;
  final b = root as SplitBranch;
  return containsPane(b.first, paneId) || containsPane(b.second, paneId);
}

/// Splits the leaf matching [paneId] into a branch: the old pane moves to
/// `first`, [newPaneId] to `second`, ratio 0.5. Unknown [paneId] → [root].
SplitNode splitLeaf(
  SplitNode root,
  String paneId,
  SplitAxis axis,
  String newPaneId,
) {
  if (root is SplitLeaf) {
    if (root.paneId != paneId) return root;
    return SplitBranch(
      axis: axis,
      ratio: 0.5,
      first: SplitLeaf(paneId),
      second: SplitLeaf(newPaneId),
    );
  }
  final b = root as SplitBranch;
  final newFirst = splitLeaf(b.first, paneId, axis, newPaneId);
  if (!identical(newFirst, b.first)) return b.copyWith(first: newFirst);
  final newSecond = splitLeaf(b.second, paneId, axis, newPaneId);
  if (!identical(newSecond, b.second)) return b.copyWith(second: newSecond);
  return root;
}

/// Removes the leaf [paneId]; its sibling collapses into the parent position.
/// Returns `null` when the removed leaf was the last one, or [root] unchanged
/// when [paneId] is unknown.
SplitNode? removePane(SplitNode root, String paneId) {
  if (root is SplitLeaf) {
    return root.paneId == paneId ? null : root;
  }
  final b = root as SplitBranch;
  if (b.first is SplitLeaf && (b.first as SplitLeaf).paneId == paneId) {
    return b.second;
  }
  if (b.second is SplitLeaf && (b.second as SplitLeaf).paneId == paneId) {
    return b.first;
  }
  if (containsPane(b.first, paneId)) {
    final nf = removePane(b.first, paneId);
    return nf == null ? b.second : b.copyWith(first: nf);
  }
  if (containsPane(b.second, paneId)) {
    final ns = removePane(b.second, paneId);
    return ns == null ? b.first : b.copyWith(second: ns);
  }
  return root;
}

/// Next leaf after [paneId] in pre-order, wrapping at the end. Single-leaf tree
/// returns that same id; unknown [paneId] → `null`.
String? nextLeaf(SplitNode root, String paneId) {
  final leaves = splitLeaves(root);
  final i = leaves.indexOf(paneId);
  if (i < 0) return null;
  return leaves[(i + 1) % leaves.length];
}

/// Previous leaf before [paneId] in pre-order, wrapping at the start.
String? prevLeaf(SplitNode root, String paneId) {
  final leaves = splitLeaves(root);
  final i = leaves.indexOf(paneId);
  if (i < 0) return null;
  return leaves[(i - 1 + leaves.length) % leaves.length];
}

/// A geometric direction for pane-to-pane focus movement.
enum PaneDirection { left, right, up, down }

/// The pane id geometrically adjacent to [paneId] on the [direction] side of
/// [root], or `null` when [paneId] is unknown or has no neighbour there.
///
/// The tree is laid out into unit rects (root = `0,0..1,1`). A
/// [SplitAxis.vertical] branch splits its rect into left/right columns at
/// [SplitBranch.ratio] ([SplitBranch.first] = left); [SplitAxis.horizontal]
/// splits into top/bottom rows ([SplitBranch.first] = top). Among panes
/// strictly on the requested side, the winner is the one whose cross-axis span
/// overlaps the source most, tie-broken by smallest distance along the
/// direction, then by pre-order index for determinism.
String? paneInDirection(
  SplitNode root,
  String paneId,
  PaneDirection direction,
) {
  const epsilon = 1e-6;
  final rects = <String, Rect>{};
  final order = <String>[];

  void layout(SplitNode node, Rect rect) {
    if (node is SplitLeaf) {
      rects[node.paneId] = rect;
      order.add(node.paneId);
      return;
    }
    final b = node as SplitBranch;
    if (b.axis == SplitAxis.vertical) {
      final w = rect.width * b.ratio;
      layout(b.first, Rect.fromLTWH(rect.left, rect.top, w, rect.height));
      layout(
        b.second,
        Rect.fromLTWH(rect.left + w, rect.top, rect.width - w, rect.height),
      );
    } else {
      final h = rect.height * b.ratio;
      layout(b.first, Rect.fromLTWH(rect.left, rect.top, rect.width, h));
      layout(
        b.second,
        Rect.fromLTWH(rect.left, rect.top + h, rect.width, rect.height - h),
      );
    }
  }

  layout(root, const Rect.fromLTWH(0, 0, 1, 1));

  final source = rects[paneId];
  if (source == null) return null;

  String? best;
  var bestOverlap = -1.0;
  var bestDistance = double.infinity;
  var bestIndex = 1 << 31;
  for (var i = 0; i < order.length; i++) {
    final id = order[i];
    if (id == paneId) continue;
    final other = rects[id]!;
    final double overlap;
    final double distance;
    switch (direction) {
      case PaneDirection.left:
        if (other.right > source.left + epsilon) continue;
        overlap = _spanOverlap(
          source.top,
          source.bottom,
          other.top,
          other.bottom,
        );
        distance = source.left - other.right;
      case PaneDirection.right:
        if (other.left < source.right - epsilon) continue;
        overlap = _spanOverlap(
          source.top,
          source.bottom,
          other.top,
          other.bottom,
        );
        distance = other.left - source.right;
      case PaneDirection.up:
        if (other.bottom > source.top + epsilon) continue;
        overlap = _spanOverlap(
          source.left,
          source.right,
          other.left,
          other.right,
        );
        distance = source.top - other.bottom;
      case PaneDirection.down:
        if (other.top < source.bottom - epsilon) continue;
        overlap = _spanOverlap(
          source.left,
          source.right,
          other.left,
          other.right,
        );
        distance = other.top - source.bottom;
    }
    if (overlap <= epsilon) continue;
    final better =
        overlap > bestOverlap + epsilon ||
        (overlap > bestOverlap - epsilon &&
            (distance < bestDistance - epsilon ||
                (distance < bestDistance + epsilon && i < bestIndex)));
    if (better) {
      best = id;
      bestOverlap = overlap;
      bestDistance = distance;
      bestIndex = i;
    }
  }
  return best;
}

/// Length of the overlap between segments `[aStart, aEnd]` and `[bStart, bEnd]`,
/// clamped to 0 when they do not overlap.
double _spanOverlap(double aStart, double aEnd, double bStart, double bEnd) {
  final lo = aStart > bStart ? aStart : bStart;
  final hi = aEnd < bEnd ? aEnd : bEnd;
  final overlap = hi - lo;
  return overlap > 0 ? overlap : 0;
}

/// Sets every branch ratio to 0.5 recursively.
SplitNode equalize(SplitNode root) {
  if (root is SplitLeaf) return root;
  final b = root as SplitBranch;
  return b.copyWith(
    ratio: 0.5,
    first: equalize(b.first),
    second: equalize(b.second),
  );
}

/// Sets the ratio on the branch that directly parents the leaf [paneId] (the
/// C# `ResizePane` target). [ratio] is clamped to 0.1..0.9. Unknown → [root].
SplitNode resizePane(SplitNode root, String paneId, double ratio) {
  if (root is SplitLeaf) return root;
  final b = root as SplitBranch;
  final clamped = ratio.clamp(0.1, 0.9).toDouble();
  final firstIsTarget =
      b.first is SplitLeaf && (b.first as SplitLeaf).paneId == paneId;
  final secondIsTarget =
      b.second is SplitLeaf && (b.second as SplitLeaf).paneId == paneId;
  if (firstIsTarget || secondIsTarget) {
    return b.copyWith(ratio: clamped);
  }
  if (containsPane(b.first, paneId)) {
    return b.copyWith(first: resizePane(b.first, paneId, ratio));
  }
  if (containsPane(b.second, paneId)) {
    return b.copyWith(second: resizePane(b.second, paneId, ratio));
  }
  return root;
}

/// Swaps the pane ids [a] and [b] in place. Either id missing → [root].
SplitNode swapPanes(SplitNode root, String a, String b) {
  if (!containsPane(root, a) || !containsPane(root, b)) return root;
  SplitNode walk(SplitNode n) {
    if (n is SplitLeaf) {
      if (n.paneId == a) return SplitLeaf(b);
      if (n.paneId == b) return SplitLeaf(a);
      return n;
    }
    final br = n as SplitBranch;
    return br.copyWith(first: walk(br.first), second: walk(br.second));
  }

  return walk(root);
}

/// The [SplitBranch] reached by following [path] (each step 0 = [SplitBranch.first],
/// 1 = [SplitBranch.second]) from [root]. Empty path targets [root] itself.
/// Returns `null` when the path leaves the tree, hits a leaf, or ends on a leaf.
SplitBranch? branchAtPath(SplitNode root, List<int> path) {
  SplitNode node = root;
  for (final step in path) {
    if (node is! SplitBranch) return null;
    switch (step) {
      case 0:
        node = node.first;
      case 1:
        node = node.second;
      default:
        return null;
    }
  }
  return node is SplitBranch ? node : null;
}

/// Returns a new tree with the branch at [path] (see [branchAtPath]) given
/// [ratio], clamped to 0.1..0.9. An unresolvable path (out of range, into a
/// leaf, or not ending on a branch) returns [root] unchanged.
SplitNode setRatioAtPath(SplitNode root, List<int> path, double ratio) {
  final clamped = ratio.clamp(0.1, 0.9).toDouble();
  SplitNode? recur(SplitNode node, int depth) {
    if (depth == path.length) {
      if (node is! SplitBranch) return null;
      return node.copyWith(ratio: clamped);
    }
    if (node is! SplitBranch) return null;
    switch (path[depth]) {
      case 0:
        final nf = recur(node.first, depth + 1);
        return nf == null ? null : node.copyWith(first: nf);
      case 1:
        final ns = recur(node.second, depth + 1);
        return ns == null ? null : node.copyWith(second: ns);
      default:
        return null;
    }
  }

  return recur(root, 0) ?? root;
}

SplitNode _spine(List<String> ids, SplitAxis axis, String label) {
  if (ids.isEmpty) {
    throw ArgumentError.value(ids, 'paneIds', '$label requires at least 1 id');
  }
  SplitNode node = SplitLeaf(ids.first);
  for (var i = 1; i < ids.length; i++) {
    node = SplitBranch(
      axis: axis,
      ratio: i / (i + 1),
      first: node,
      second: SplitLeaf(ids[i]),
    );
  }
  return node;
}

/// Left-leaning vertical spine of equal columns. Consumes [paneIds] in order
/// (leftmost first). Requires >= 1 id; single id → [SplitLeaf].
SplitNode buildColumns(List<String> paneIds) =>
    _spine(paneIds, SplitAxis.vertical, 'buildColumns');

/// Left-leaning horizontal spine of equal rows. Consumes [paneIds] in order
/// (topmost first). Requires >= 1 id; single id → [SplitLeaf].
SplitNode buildRows(List<String> paneIds) =>
    _spine(paneIds, SplitAxis.horizontal, 'buildRows');

/// A 2x2 grid. Requires exactly 4 ids, laid out row-major (top-left, top-right,
/// bottom-left, bottom-right): outer horizontal split, each half split
/// vertically, all ratios 0.5.
SplitNode buildGrid2x2(List<String> paneIds) {
  if (paneIds.length != 4) {
    throw ArgumentError.value(
      paneIds,
      'paneIds',
      'buildGrid2x2 requires exactly 4 ids',
    );
  }
  return SplitBranch(
    axis: SplitAxis.horizontal,
    ratio: 0.5,
    first: SplitBranch(
      axis: SplitAxis.vertical,
      ratio: 0.5,
      first: SplitLeaf(paneIds[0]),
      second: SplitLeaf(paneIds[1]),
    ),
    second: SplitBranch(
      axis: SplitAxis.vertical,
      ratio: 0.5,
      first: SplitLeaf(paneIds[2]),
      second: SplitLeaf(paneIds[3]),
    ),
  );
}

/// Main pane (first id) at ratio 0.6 beside a horizontal stack of the rest.
/// Requires >= 1 id; single id → [SplitLeaf].
SplitNode buildMainStack(List<String> paneIds) {
  if (paneIds.isEmpty) {
    throw ArgumentError.value(
      paneIds,
      'paneIds',
      'buildMainStack requires at least 1 id',
    );
  }
  if (paneIds.length == 1) return SplitLeaf(paneIds.first);
  final stack = _spine(paneIds.sublist(1), SplitAxis.horizontal, 'buildMainStack');
  return SplitBranch(
    axis: SplitAxis.vertical,
    ratio: 0.6,
    first: SplitLeaf(paneIds.first),
    second: stack,
  );
}

String _axisToJson(SplitAxis axis) =>
    axis == SplitAxis.horizontal ? 'Horizontal' : 'Vertical';

SplitAxis _axisFromJson(Object? raw) =>
    raw == 'Horizontal' ? SplitAxis.horizontal : SplitAxis.vertical;

/// Encodes [node] to the C# `SplitNodeState` JSON shape.
JsonMap splitNodeToJson(SplitNode node) {
  if (node is SplitLeaf) {
    return {
      'isLeaf': true,
      'paneId': node.paneId,
      'direction': 'Vertical',
      'splitRatio': 0.5,
      'first': null,
      'second': null,
    };
  }
  final b = node as SplitBranch;
  return {
    'isLeaf': false,
    'paneId': null,
    'direction': _axisToJson(b.axis),
    'splitRatio': b.ratio,
    'first': splitNodeToJson(b.first),
    'second': splitNodeToJson(b.second),
  };
}

/// Defensively decodes a `SplitNodeState` tree. Malformed or missing required
/// fields → `null` so a corrupt persisted tree degrades gracefully.
SplitNode? splitNodeFromJson(Object? json) {
  if (json is! Map) return null;
  final isLeaf = json['isLeaf'];
  if (isLeaf is! bool) return null;
  if (isLeaf) {
    final paneId = json['paneId'];
    if (paneId is! String) return null;
    return SplitLeaf(paneId);
  }
  final first = splitNodeFromJson(json['first']);
  final second = splitNodeFromJson(json['second']);
  if (first == null || second == null) return null;
  final rawRatio = json['splitRatio'];
  final ratio = rawRatio is num ? rawRatio.toDouble() : 0.5;
  return SplitBranch(
    axis: _axisFromJson(json['direction']),
    ratio: ratio,
    first: first,
    second: second,
  );
}
