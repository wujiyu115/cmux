import 'command_bus.dart';
import 'command_ids.dart';

/// Holds the foreground search-in-files opener for the Ctrl/Cmd+Shift+F
/// shortcut.
///
/// Kept-alive workspace tabs bind/unbind when their route becomes
/// active/inactive (see [WorkspaceSplitPane]) — the same shape as
/// [QuickOpenHost].
class SearchHost {
  void Function()? _openSearch;

  void bind(void Function() openSearch) => _openSearch = openSearch;

  void unbind(void Function() openSearch) {
    if (identical(_openSearch, openSearch)) _openSearch = null;
  }

  void clear() => _openSearch = null;

  void open() => _openSearch?.call();
}

/// Wires [CommandIds.searchInFiles] onto [bus] against [host].
///
/// Call once during app bootstrap (see `buildAppShell`).
void registerSearchInFilesCommand(CommandBus bus, SearchHost host) {
  bus.register(CommandIds.searchInFiles, () => host.open());
}
