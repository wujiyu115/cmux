import '../../l10n/app_localizations.dart';

/// Relative time for the blame bar: just now → minutes → hours → days →
/// weeks → months → years (VS Code hover granularity). Sibling of
/// [formatCoarseRelativeTime], which stops at days for notification tiles.
String formatBlameRelativeTime(
  AppLocalizations l10n,
  DateTime time, {
  DateTime? now,
}) {
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inMinutes < 1) return l10n.notificationTimeJustNow;
  if (diff.inHours < 1) {
    return l10n.notificationTimeMinutesAgo(diff.inMinutes);
  }
  if (diff.inDays < 1) {
    return l10n.notificationTimeHoursAgo(diff.inHours);
  }
  if (diff.inDays < 30) {
    return l10n.blameTimeDaysAgo(diff.inDays);
  }
  final months = (diff.inDays / 30).floor();
  if (months < 12) {
    return l10n.blameTimeMonthsAgo(months);
  }
  final years = (diff.inDays / 365).floor();
  if (years < 1) {
    return l10n.blameTimeMonthsAgo(months);
  }
  return l10n.blameTimeYearsAgo(years);
}
