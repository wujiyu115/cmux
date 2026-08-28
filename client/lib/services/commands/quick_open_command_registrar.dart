import 'command_bus.dart';
import 'command_ids.dart';

/// Holds the foreground quick-open opener for the Ctrl+P shortcut.
///
/// Kept-alive workspace tabs bind/unbind when their route becomes
/// active/inactive (see [WorkspaceSplitPane]).
class QuickOpenHost {
  void Function()? _openQuickOpen;

  void bind(void Function() openQuickOpen) => _openQuickOpen = openQuickOpen;

  void unbind(void Function() openQuickOpen) {
    if (identical(_openQuickOpen, openQuickOpen)) _openQuickOpen = null;
  }

  void clear() => _openQuickOpen = null;

  void open() => _openQuickOpen?.call();
}

/// Wires [CommandIds.quickOpen] onto [bus] against [host].
///
/// Call once during app bootstrap (see `buildAppShell`).
void registerQuickOpenCommands(CommandBus bus, QuickOpenHost host) {
  bus.register(CommandIds.quickOpen, () => host.open());
}
