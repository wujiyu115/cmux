import 'package:flutter/foundation.dart';

import 'command_bus.dart';
import 'command_ids.dart';

/// Claims [CommandIds.editorGotoLine] (Mod+G) for a focused editor pane.
///
/// Editor panes claim when their subtree gains focus and release on blur, so
/// the shortcut always targets the focused editor — several panes can be alive
/// at once (kept-alive workspace tabs mount their last file tab offstage).
///
/// Returns a disposer that unregisters exactly the handler it registered
/// (identity-guarded via [CommandBus.unregister], so a stale disposer never
/// clobbers another pane's claim).
VoidCallback claimEditorGotoLineCommand(CommandBus bus, VoidCallback openGotoLine) {
  bus.register(CommandIds.editorGotoLine, openGotoLine);
  return () => bus.unregister(CommandIds.editorGotoLine, openGotoLine);
}
