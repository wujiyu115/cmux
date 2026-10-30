import 'package:flutter/foundation.dart';

/// How the weekday/time window in [BarkPushSchedule] filters phone pushes.
enum BarkPushScheduleMode {
  /// No window: every notice that passes the other gates is pushed.
  off,

  /// Allowlist: push only inside the window.
  allow,

  /// Blocklist: push only outside the window.
  block;

  static BarkPushScheduleMode fromName(Object? raw) =>
      BarkPushScheduleMode.values.firstWhere(
        (mode) => mode.name == raw,
        orElse: () => BarkPushScheduleMode.off,
      );
}

/// Weekday + time-of-day window for phone pushes, in the desktop's local time.
///
/// A window whose start is later than its end wraps over midnight (22:00–07:00),
/// and [days] then names the *start* day: Friday 22:00–07:00 means Friday night
/// into Saturday morning. Equal start and end means the whole selected days.
///
/// An empty [days] set is treated as "every day" so a schedule can never end up
/// silently suppressing every push because the user deselected the last day.
@immutable
class BarkPushSchedule {
  const BarkPushSchedule({
    this.mode = BarkPushScheduleMode.off,
    this.days = allWeekdays,
    this.startMinute = 9 * 60,
    this.endMinute = 18 * 60,
  });

  static const allWeekdays = <int>{
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
    DateTime.sunday,
  };

  static const minutesPerDay = 24 * 60;

  /// Mode defaults to [BarkPushScheduleMode.off], so the window values below are
  /// only what a user starts editing from.
  final BarkPushScheduleMode mode;

  /// ISO weekdays (1 = Monday … 7 = Sunday) the window applies to.
  final Set<int> days;

  /// Minutes after midnight the window opens (inclusive).
  final int startMinute;

  /// Minutes after midnight the window closes (exclusive).
  final int endMinute;

  bool get isActive => mode != BarkPushScheduleMode.off;

  /// Whether the window itself covers [local] on its wall clock, ignoring
  /// [mode] — the whitelist/blacklist decision is [allows].
  bool contains(DateTime local) {
    final activeDays = days.isEmpty ? allWeekdays : days;
    final minute = local.hour * 60 + local.minute;
    if (startMinute == endMinute) {
      // A zero-length window would be a dead schedule; read it as all day.
      return activeDays.contains(local.weekday);
    }
    if (startMinute < endMinute) {
      return activeDays.contains(local.weekday) &&
          minute >= startMinute &&
          minute < endMinute;
    }
    // Overnight window: the tail belongs to the day the window started on.
    if (minute >= startMinute) return activeDays.contains(local.weekday);
    if (minute < endMinute) {
      return activeDays.contains(_previousWeekday(local.weekday));
    }
    return false;
  }

  /// The gate the push dispatcher applies: `true` means "push this notice now".
  bool allows(DateTime local) => switch (mode) {
    BarkPushScheduleMode.off => true,
    BarkPushScheduleMode.allow => contains(local),
    BarkPushScheduleMode.block => !contains(local),
  };

  static int _previousWeekday(int weekday) =>
      weekday == DateTime.monday ? DateTime.sunday : weekday - 1;

  BarkPushSchedule copyWith({
    BarkPushScheduleMode? mode,
    Set<int>? days,
    int? startMinute,
    int? endMinute,
  }) => BarkPushSchedule(
    mode: mode ?? this.mode,
    days: days ?? this.days,
    startMinute: startMinute ?? this.startMinute,
    endMinute: endMinute ?? this.endMinute,
  );

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'days': days.toList()..sort(),
    'startMinute': startMinute,
    'endMinute': endMinute,
  };

  factory BarkPushSchedule.fromJson(Object? raw) {
    if (raw is! Map) return const BarkPushSchedule();
    final json = raw.cast<String, Object?>();
    final rawDays = json['days'];
    final days = <int>{
      if (rawDays is List)
        for (final day in rawDays)
          if (day is int && day >= DateTime.monday && day <= DateTime.sunday)
            day,
    };
    return BarkPushSchedule(
      mode: BarkPushScheduleMode.fromName(json['mode']),
      days: days.isEmpty ? allWeekdays : Set<int>.unmodifiable(days),
      startMinute: _minuteOr(json['startMinute'], 9 * 60),
      endMinute: _minuteOr(json['endMinute'], 18 * 60),
    );
  }

  static int _minuteOr(Object? raw, int fallback) =>
      raw is int && raw >= 0 && raw < minutesPerDay ? raw : fallback;

  @override
  bool operator ==(Object other) =>
      other is BarkPushSchedule &&
      other.mode == mode &&
      other.startMinute == startMinute &&
      other.endMinute == endMinute &&
      setEquals(other.days, days);

  @override
  int get hashCode => Object.hash(
    mode,
    startMinute,
    endMinute,
    Object.hashAllUnordered(days),
  );
}