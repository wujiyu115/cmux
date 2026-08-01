import '../../../l10n/app_localizations.dart';

/// Localized display name for a toolbar key group.
///
/// Group ids are stable storage keys, names are UI, and keeping the mapping here
/// lets `models/toolbar_key.dart` stay a pure data file with no l10n dependency.
/// Key-cap labels stay unlocalized on purpose — `^C` / `Esc` / `F1` are terminal
/// notation, identical in every locale.
String toolbarGroupLabel(String groupId, AppLocalizations l10n) =>
    switch (groupId) {
      'arrows' => l10n.mobileToolbarGroupArrows,
      'clipboard' => l10n.mobileToolbarGroupClipboard,
      'terminal_ctrl' => l10n.mobileToolbarGroupTerminalCtrl,
      'signals' => l10n.mobileToolbarGroupSignals,
      'symbols1' => l10n.mobileToolbarGroupSymbols1,
      'navigation' => l10n.mobileToolbarGroupNavigation,
      'editing' => l10n.mobileToolbarGroupEditing,
      'search' => l10n.mobileToolbarGroupSearch,
      'punctuation' => l10n.mobileToolbarGroupPunctuation,
      'symbols2' => l10n.mobileToolbarGroupSymbols2,
      'brackets1' => l10n.mobileToolbarGroupBrackets1,
      'brackets2' => l10n.mobileToolbarGroupBrackets2,
      'fkeys1' => l10n.mobileToolbarGroupFkeys1,
      'fkeys2' => l10n.mobileToolbarGroupFkeys2,
      'fkeys3' => l10n.mobileToolbarGroupFkeys3,
      'advanced' => l10n.mobileToolbarGroupAdvanced,
      _ => groupId,
    };
