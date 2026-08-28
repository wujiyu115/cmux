import '../../l10n/app_localizations.dart';
import 'command_catalog.dart';
import 'command_definition.dart';

/// Display title for [commandId], resolved via the catalog's
/// `titleL10nKey` into the matching generated [AppLocalizations] getter.
///
/// Returns [commandId] unchanged if it is not in [CommandCatalog.v1] or has
/// no matching l10n key (should not happen for catalog commands; guards
/// against a future catalog/ARB drift crashing the settings UI).
String titleForCommand(AppLocalizations l10n, String commandId) {
  for (final def in CommandCatalog.v1) {
    if (def.id == commandId) {
      if (def.titleL10nKey == 'shortcutsStripFocusTab') {
        final ordinal = _stripFocusTabOrdinal(commandId);
        if (ordinal != null) {
          return l10n.shortcutsStripFocusTab(ordinal);
        }
      }
      return _titleForKey(l10n, def.titleL10nKey) ?? commandId;
    }
  }
  return commandId;
}

/// Parses `workbench.strip.focusTabN` → N, or null if not a focus-tab id.
int? _stripFocusTabOrdinal(String commandId) {
  const prefix = 'workbench.strip.focusTab';
  if (!commandId.startsWith(prefix)) return null;
  return int.tryParse(commandId.substring(prefix.length));
}

/// Display name for a [CommandCategory] settings group.
String titleForCategory(AppLocalizations l10n, CommandCategory category) {
  return switch (category) {
    CommandCategory.navigation => l10n.shortcutsCategoryNavigation,
    CommandCategory.tabs => l10n.shortcutsCategoryTabs,
    CommandCategory.view => l10n.shortcutsCategoryView,
    CommandCategory.zoom => l10n.shortcutsCategoryZoom,
    CommandCategory.compose => l10n.shortcutsCategoryCompose,
    CommandCategory.run => l10n.shortcutsCategoryRun,
    CommandCategory.meta => l10n.shortcutsCategoryMeta,
    CommandCategory.terminal => l10n.shortcutsCategoryTerminal,
  };
}

String? _titleForKey(AppLocalizations l10n, String titleL10nKey) {
  return switch (titleL10nKey) {
    'shortcutsWorkspaceNextTab' => l10n.shortcutsWorkspaceNextTab,
    'shortcutsWorkspacePrevTab' => l10n.shortcutsWorkspacePrevTab,
    'shortcutsWorkspaceCloseTab' => l10n.shortcutsWorkspaceCloseTab,
    'shortcutsWorkspaceReopenClosed' => l10n.shortcutsWorkspaceReopenClosed,
    'shortcutsWorkspaceSearch' => l10n.shortcutsWorkspaceSearch,
    'shortcutsQuickOpen' => l10n.shortcutsQuickOpen,
    'shortcutsStripNextTab' => l10n.shortcutsStripNextTab,
    'shortcutsStripPrevTab' => l10n.shortcutsStripPrevTab,
    'shortcutsSessionNewTab' => l10n.shortcutsSessionNewTab,
    'shortcutsSessionCloseTab' => l10n.shortcutsSessionCloseTab,
    'shortcutsToggleSidebar' => l10n.shortcutsToggleSidebar,
    'shortcutsTogglePanel' => l10n.shortcutsTogglePanel,
    'shortcutsToggleSecondarySidebar' => l10n.shortcutsToggleSecondarySidebar,
    'shortcutsZoomIn' => l10n.shortcutsZoomIn,
    'shortcutsZoomOut' => l10n.shortcutsZoomOut,
    'shortcutsZoomReset' => l10n.shortcutsZoomReset,
    'shortcutsComposeSubmit' => l10n.shortcutsComposeSubmit,
    'shortcutsComposeNewline' => l10n.shortcutsComposeNewline,
    'shortcutsShowCheatsheet' => l10n.shortcutsShowCheatsheet,
    'shortcutsRunSelected' => l10n.shortcutsRunSelected,
    'shortcutsRunStop' => l10n.shortcutsRunStop,
    'shortcutsRunRestart' => l10n.shortcutsRunRestart,
    'shortcutsCommandPalette' => l10n.shortcutsCommandPalette,
    'shortcutsTerminalSplitRight' => l10n.shortcutsTerminalSplitRight,
    'shortcutsTerminalSplitDown' => l10n.shortcutsTerminalSplitDown,
    'shortcutsTerminalFocusNextPane' => l10n.shortcutsTerminalFocusNextPane,
    'shortcutsTerminalFocusPrevPane' => l10n.shortcutsTerminalFocusPrevPane,
    'shortcutsTerminalFocusPaneLeft' => l10n.shortcutsTerminalFocusPaneLeft,
    'shortcutsTerminalFocusPaneRight' => l10n.shortcutsTerminalFocusPaneRight,
    'shortcutsTerminalFocusPaneUp' => l10n.shortcutsTerminalFocusPaneUp,
    'shortcutsTerminalFocusPaneDown' => l10n.shortcutsTerminalFocusPaneDown,
    'shortcutsTerminalZoomPane' => l10n.shortcutsTerminalZoomPane,
    'shortcutsTerminalEqualizePanes' => l10n.shortcutsTerminalEqualizePanes,
    'shortcutsTerminalClosePane' => l10n.shortcutsTerminalClosePane,
    'shortcutsTerminalLayoutSingle' => l10n.shortcutsTerminalLayoutSingle,
    'shortcutsTerminalLayoutColumns2' => l10n.shortcutsTerminalLayoutColumns2,
    'shortcutsTerminalLayoutColumns3' => l10n.shortcutsTerminalLayoutColumns3,
    'shortcutsTerminalLayoutGrid' => l10n.shortcutsTerminalLayoutGrid,
    'shortcutsTerminalLayoutMainStack' => l10n.shortcutsTerminalLayoutMainStack,
    'shortcutsTerminalCommandLog' => l10n.shortcutsTerminalCommandLog,
    'shortcutsTerminalCommandHistory' => l10n.shortcutsTerminalCommandHistory,
    _ => null,
  };
}
