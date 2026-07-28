/// Immutable terminal surface (tab): a split tree plus focus, per-pane custom
/// names, and an optional zoomed pane. JSON matches the C# `SurfaceState`.
library;

import 'terminal_split.dart';

/// A single terminal tab. Immutable; mutators return new instances.
class TerminalSurface {
  TerminalSurface({
    required this.id,
    required this.name,
    required this.root,
    required this.focusedPaneId,
    Map<String, String> paneNames = const {},
    this.zoomedPaneId,
  })  : paneNames = Map.unmodifiable(paneNames),
        assert(
          _leafIds(root).contains(focusedPaneId),
          'focusedPaneId must be one of root\'s leaves',
        );

  /// A one-leaf surface focused on [paneId].
  factory TerminalSurface.single({
    required String id,
    required String name,
    required String paneId,
  }) {
    return TerminalSurface(
      id: id,
      name: name,
      root: SplitLeaf(paneId),
      focusedPaneId: paneId,
    );
  }

  final String id;
  final String name;
  final SplitNode root;
  final String focusedPaneId;

  /// paneId -> custom display name.
  final Map<String, String> paneNames;

  /// The pane currently maximized, or `null` when none is zoomed.
  final String? zoomedPaneId;

  /// Pre-order pane ids (the canonical pane order).
  List<String> get paneIds => splitLeaves(root);

  /// Custom name for [paneId], or `''` when none is set.
  String displayNameFor(String paneId) => paneNames[paneId] ?? '';

  TerminalSurface copyWith({
    String? id,
    String? name,
    SplitNode? root,
    String? focusedPaneId,
    Map<String, String>? paneNames,
    String? zoomedPaneId,
    bool clearZoom = false,
  }) {
    return TerminalSurface(
      id: id ?? this.id,
      name: name ?? this.name,
      root: root ?? this.root,
      focusedPaneId: focusedPaneId ?? this.focusedPaneId,
      paneNames: paneNames ?? this.paneNames,
      zoomedPaneId: clearZoom ? null : (zoomedPaneId ?? this.zoomedPaneId),
    );
  }

  /// Removes [paneId] from the tree, drops its custom name, migrates focus to
  /// the pre-order-nearest survivor if it was focused, and clears the zoom if
  /// it pointed at the removed pane. Throws [StateError] if it was the last
  /// pane (callers must guard — the final pane cannot be closed).
  TerminalSurface withPaneRemoved(String paneId) {
    final leaves = splitLeaves(root);
    final newRoot = removePane(root, paneId);
    if (newRoot == null) {
      throw StateError('Cannot remove the last pane');
    }
    var newFocus = focusedPaneId;
    if (focusedPaneId == paneId) {
      final idx = leaves.indexOf(paneId);
      newFocus = idx + 1 < leaves.length ? leaves[idx + 1] : leaves[idx - 1];
    }
    final newNames = Map<String, String>.from(paneNames)..remove(paneId);
    final newZoom = zoomedPaneId == paneId ? null : zoomedPaneId;
    return TerminalSurface(
      id: id,
      name: name,
      root: newRoot,
      focusedPaneId: newFocus,
      paneNames: newNames,
      zoomedPaneId: newZoom,
    );
  }

  /// Encodes to the C# `SurfaceState` JSON shape. `zoomedPaneId` is a
  /// TeamPilot-only extension (absent from the C# model).
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'rootNode': splitNodeToJson(root),
      'focusedPaneId': focusedPaneId,
      'paneCustomNames': Map<String, String>.from(paneNames),
      'zoomedPaneId': zoomedPaneId,
    };
  }

  /// Defensively decodes a `SurfaceState`. Malformed input → `null`. A focus or
  /// zoom that no longer names a live leaf is repaired rather than rejected.
  static TerminalSurface? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String) return null;
    final root = splitNodeFromJson(json['rootNode']);
    if (root == null) return null;
    final leaves = splitLeaves(root);

    final rawFocus = json['focusedPaneId'];
    final focusedPaneId = (rawFocus is String && leaves.contains(rawFocus))
        ? rawFocus
        : leaves.first;

    final names = <String, String>{};
    final rawNames = json['paneCustomNames'];
    if (rawNames is Map) {
      rawNames.forEach((key, value) {
        if (key is String && value is String) names[key] = value;
      });
    }

    final rawZoom = json['zoomedPaneId'];
    final zoomedPaneId =
        (rawZoom is String && leaves.contains(rawZoom)) ? rawZoom : null;

    return TerminalSurface(
      id: id,
      name: name,
      root: root,
      focusedPaneId: focusedPaneId,
      paneNames: names,
      zoomedPaneId: zoomedPaneId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TerminalSurface &&
          other.id == id &&
          other.name == name &&
          other.root == root &&
          other.focusedPaneId == focusedPaneId &&
          other.zoomedPaneId == zoomedPaneId &&
          _mapEquals(other.paneNames, paneNames));

  @override
  int get hashCode => Object.hash(
        id,
        name,
        root,
        focusedPaneId,
        zoomedPaneId,
        Object.hashAllUnordered(
          [for (final e in paneNames.entries) Object.hash(e.key, e.value)],
        ),
      );

  @override
  String toString() =>
      'TerminalSurface($id, $name, focus=$focusedPaneId, zoom=$zoomedPaneId)';
}

List<String> _leafIds(SplitNode root) => splitLeaves(root);

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
