import '../../pages/command_palette/command_palette_overlay.dart';
import '../../repositories/command_mru_repository.dart';
import '../../router/app_router.dart';
import '../../widgets/shortcuts/shortcut_cheatsheet_dialog.dart';
import 'command_bus.dart';
import 'command_ids.dart';

/// Wires [CommandIds.showCheatsheet] onto [bus].
///
/// The command has no natural "owning" widget, so it reaches the UI through
/// the app's root [appRouter] navigator rather than a per-widget handler —
/// call once during app bootstrap, alongside `registerLayoutCommands` /
/// `registerSessionCommands`.
void registerShortcutsUiCommands(CommandBus bus) {
  bus.register(CommandIds.showCheatsheet, () {
    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null) return;
    showShortcutCheatsheetDialog(context);
  });
}

/// Wires [CommandIds.commandPalette] onto [bus].
///
/// Like [registerShortcutsUiCommands], the palette has no owning widget, so it
/// opens through the root [appRouter] navigator. The palette returns the
/// selected id out of its route; [showCommandPalette] then records it in
/// [mruRepository] and re-invokes it on [bus]. Call once during app bootstrap.
void registerCommandPaletteCommand(
  CommandBus bus, {
  CommandMruRepository? mruRepository,
}) {
  final mru = mruRepository ?? CommandMruRepository();
  bus.register(CommandIds.commandPalette, () {
    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null) return;
    showCommandPalette(context, bus: bus, mruRepository: mru);
  });
}
