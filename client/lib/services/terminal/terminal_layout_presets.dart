/// Lossless terminal-layout presets.
///
/// A preset rebuilds a [TerminalSurface]'s split tree into a fixed *shape*
/// (single pane, N columns, a 2x2 grid, a main+stack) while **reusing every
/// live pane** — no pane is ever destroyed to fit the shape. This is the
/// product red line: applying a layout must never kill a running terminal.
///
/// Pure module: only the split-tree / surface models are imported, no Flutter.
library;

import '../../models/terminal_split.dart';
import '../../models/terminal_surface.dart';

/// The available layout shapes offered by the split toolbar.
enum TerminalLayoutPreset { single, columns2, columns3, grid2x2, mainStack }

/// What to do when the surface holds more live panes than the preset has slots.
///
/// [stackIntoLast] fills the leading slots one pane each, then stacks every
/// remaining pane into the final slot (a [buildRows] spine) — nothing dropped.
enum PresetOverflowPolicy { stackIntoLast }

/// Number of top-level slots a [preset] exposes.
int presetSlotCount(TerminalLayoutPreset preset) {
  switch (preset) {
    case TerminalLayoutPreset.single:
      return 1;
    case TerminalLayoutPreset.columns2:
      return 2;
    case TerminalLayoutPreset.columns3:
      return 3;
    case TerminalLayoutPreset.grid2x2:
      return 4;
    case TerminalLayoutPreset.mainStack:
      return 3;
  }
}

/// Rebuilds [surface]'s tree into [preset]'s shape, reusing every live pane.
///
/// [paneIds] is the pane order to fill slots with — normally the surface's
/// current pre-order leaves plus any freshly spawned ids appended. It must be
/// non-empty (throws [ArgumentError] otherwise) and its entries are consumed in
/// order.
///
/// * `paneIds.length == slotCount` → straight preset build.
/// * `paneIds.length < slotCount` → the preset is built for just the ids
///   present (a narrower spine; [grid2x2] with < 4 ids falls back to a
///   main+stack shape). No id is dropped and it never throws.
/// * `paneIds.length > slotCount` with [PresetOverflowPolicy.stackIntoLast] →
///   the first `slotCount - 1` ids each own a slot and **all** remaining ids are
///   stacked into the last slot as a [buildRows] spine. No id is ever dropped;
///   the result's [splitLeaves] is always a permutation of [paneIds].
///
/// [focusedPaneId] is preserved when it still appears in [paneIds], otherwise it
/// becomes the first id. [zoomedPaneId] is cleared unless it is still present.
/// [paneNames] entries for ids not in [paneIds] are dropped.
TerminalSurface applyLayoutPreset(
  TerminalSurface surface,
  TerminalLayoutPreset preset, {
  required List<String> paneIds,
  PresetOverflowPolicy overflow = PresetOverflowPolicy.stackIntoLast,
}) {
  if (paneIds.isEmpty) {
    throw ArgumentError.value(paneIds, 'paneIds', 'must be non-empty');
  }
  if (paneIds.toSet().length != paneIds.length) {
    // Duplicates would break the exactly-once losslessness guarantee.
    throw ArgumentError.value(paneIds, 'paneIds', 'must not contain duplicates');
  }
  final slots = presetSlotCount(preset);
  final root = paneIds.length <= slots
      ? _buildExactOrFewer(preset, paneIds)
      : _buildOverflow(preset, paneIds, overflow);

  final idSet = paneIds.toSet();
  final focus =
      idSet.contains(surface.focusedPaneId) ? surface.focusedPaneId : paneIds.first;
  final zoom = surface.zoomedPaneId;
  final keepZoom = zoom != null && idSet.contains(zoom);
  final names = <String, String>{
    for (final entry in surface.paneNames.entries)
      if (idSet.contains(entry.key)) entry.key: entry.value,
  };

  return TerminalSurface(
    id: surface.id,
    name: surface.name,
    root: root,
    focusedPaneId: focus,
    paneNames: names,
    zoomedPaneId: keepZoom ? zoom : null,
  );
}

/// Builds the preset shape when there are at most [presetSlotCount] ids.
SplitNode _buildExactOrFewer(
  TerminalLayoutPreset preset,
  List<String> paneIds,
) {
  switch (preset) {
    case TerminalLayoutPreset.single:
      // slotCount 1, so paneIds.length is exactly 1 here.
      return SplitLeaf(paneIds.first);
    case TerminalLayoutPreset.columns2:
    case TerminalLayoutPreset.columns3:
      return buildColumns(paneIds);
    case TerminalLayoutPreset.grid2x2:
      // Exactly 4 → true grid; 3 → main+stack; 1-2 → columns. Nothing dropped.
      if (paneIds.length == 4) return buildGrid2x2(paneIds);
      if (paneIds.length == 3) return buildMainStack(paneIds);
      return buildColumns(paneIds);
    case TerminalLayoutPreset.mainStack:
      return buildMainStack(paneIds);
  }
}

/// Builds the preset shape when there are more ids than slots: lead ids each get
/// a slot, the rest are stacked (rows) into the last slot.
SplitNode _buildOverflow(
  TerminalLayoutPreset preset,
  List<String> paneIds,
  PresetOverflowPolicy overflow,
) {
  // Only one policy exists today; the switch pins future additions.
  switch (overflow) {
    case PresetOverflowPolicy.stackIntoLast:
      break;
  }
  final slots = presetSlotCount(preset);
  final leadCount = slots - 1;
  final slotNodes = <SplitNode>[
    for (var i = 0; i < leadCount; i++) SplitLeaf(paneIds[i]),
    buildRows(paneIds.sublist(leadCount)),
  ];

  switch (preset) {
    case TerminalLayoutPreset.single:
      // slotCount 1 → the single slot holds the whole rows spine.
      return slotNodes.first;
    case TerminalLayoutPreset.columns2:
    case TerminalLayoutPreset.columns3:
      return _spineNodes(slotNodes, SplitAxis.vertical);
    case TerminalLayoutPreset.grid2x2:
      // Row-major 2x2: outer horizontal, each half split vertically.
      return SplitBranch(
        axis: SplitAxis.horizontal,
        ratio: 0.5,
        first: SplitBranch(
          axis: SplitAxis.vertical,
          ratio: 0.5,
          first: slotNodes[0],
          second: slotNodes[1],
        ),
        second: SplitBranch(
          axis: SplitAxis.vertical,
          ratio: 0.5,
          first: slotNodes[2],
          second: slotNodes[3],
        ),
      );
    case TerminalLayoutPreset.mainStack:
      // Main pane at 0.6 beside a horizontal stack of the remaining slots.
      return SplitBranch(
        axis: SplitAxis.vertical,
        ratio: 0.6,
        first: slotNodes.first,
        second: _spineNodes(slotNodes.sublist(1), SplitAxis.horizontal),
      );
  }
}

/// Left-leaning spine over pre-built [nodes] along [axis], mirroring the ratio
/// progression of [buildColumns] / [buildRows].
SplitNode _spineNodes(List<SplitNode> nodes, SplitAxis axis) {
  var node = nodes.first;
  for (var i = 1; i < nodes.length; i++) {
    node = SplitBranch(
      axis: axis,
      ratio: i / (i + 1),
      first: node,
      second: nodes[i],
    );
  }
  return node;
}
