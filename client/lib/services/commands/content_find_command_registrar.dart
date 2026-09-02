import 'package:flutter/foundation.dart';

import 'command_bus.dart';
import 'command_ids.dart';

/// Claims [CommandIds.contentFind] (Mod+F) for a focused content surface.
///
/// Terminal surfaces (the chat session terminal and the workspace shell
/// terminal) claim when their subtree gains focus and release on blur, so the
/// shortcut always targets the focused terminal. Editor panes need no claim:
/// re-editor binds Ctrl/Cmd+F to its own find controller internally.
///
/// Returns a disposer that unregisters exactly the handler it registered
/// (identity-guarded via [CommandBus.unregister], so a stale disposer never
/// clobbers another surface's claim).
VoidCallback claimContentFindCommand(CommandBus bus, void Function() openFind) {
  bus.register(CommandIds.contentFind, openFind);
  return () => bus.unregister(CommandIds.contentFind, openFind);
}
