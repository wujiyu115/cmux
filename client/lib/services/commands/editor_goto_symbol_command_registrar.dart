import 'package:flutter/foundation.dart';

import 'command_bus.dart';
import 'command_ids.dart';

/// Claims [CommandIds.editorGotoSymbol] (Mod+Shift+O) for a focused editor
/// pane — same focus-gated claim shape as the go-to-line registrar.
///
/// Returns a disposer that unregisters exactly the handler it registered
/// (identity-guarded via [CommandBus.unregister]).
VoidCallback claimEditorGotoSymbolCommand(
  CommandBus bus,
  VoidCallback openGotoSymbol,
) {
  bus.register(CommandIds.editorGotoSymbol, openGotoSymbol);
  return () => bus.unregister(CommandIds.editorGotoSymbol, openGotoSymbol);
}
