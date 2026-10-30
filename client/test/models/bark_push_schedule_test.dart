import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/bark_push_schedule.dart';
import 'package:teampilot/models/bark_push_settings.dart';

void main() {
  /// Friday 2026-10-30 (weekday 5) at [hour]:[minute].
  DateTime fri(int hour, int minute) => DateTime(2026, 10, 30, hour, minute);

  const workHours = BarkPushSchedule(
    mode: BarkPushScheduleMode.allow,
    days: {DateTime.monday, DateTime.friday},
    startMinute: 9 * 60,
    endMinute: 18 * 60,
  );

  group('BarkPushSchedule.contains', () {
    test('daytime window is half-open and day-scoped', () {
      expect(workHours.contains(fri(9, 0)), isTrue);
      expect(workHours.contains(fri(17, 59)), isTrue);
      expect(workHours.contains(fri(18, 0)), isFalse); // End is exclusive.
      expect(workHours.contains(fri(8, 59)), isFalse);
      // Saturday is not selected even though the clock time matches.
      expect(workHours.contains(DateTime(2026, 10, 31, 12)), isFalse);
    });

    test('overnight window belongs to its start day', () {
      const nights = BarkPushSchedule(
        days: {DateTime.friday},
        startMinute: 22 * 60,
        endMinute: 7 * 60,
      );
      expect(nights.contains(fri(22, 0)), isTrue);
      expect(nights.contains(fri(23, 59)), isTrue);
      // Saturday 02:00 is still Friday night.
      expect(nights.contains(DateTime(2026, 10, 31, 2)), isTrue);
      expect(nights.contains(DateTime(2026, 10, 31, 6, 59)), isTrue);
      expect(nights.contains(DateTime(2026, 10, 31, 7)), isFalse);
      expect(nights.contains(DateTime(2026, 10, 31, 21)), isFalse);
      // Saturday night is not selected.
      expect(nights.contains(DateTime(2026, 10, 31, 23)), isFalse);
      // Sunday 02:00 would be the tail of Saturday night.
      expect(nights.contains(DateTime(2026, 11, 1, 2)), isFalse);
    });

    test('equal start and end means the whole selected day', () {
      const allDay = BarkPushSchedule(
        days: {DateTime.friday},
        startMinute: 12 * 60,
        endMinute: 12 * 60,
      );
      expect(allDay.contains(fri(0, 0)), isTrue);
      expect(allDay.contains(fri(23, 59)), isTrue);
      expect(allDay.contains(DateTime(2026, 10, 31, 12)), isFalse);
    });

    test('an empty day set means every day', () {
      const everyDay = BarkPushSchedule(
        days: <int>{},
        startMinute: 9 * 60,
        endMinute: 18 * 60,
      );
      expect(everyDay.contains(DateTime(2026, 11, 1, 12)), isTrue);
    });
  });

  group('BarkPushSchedule.allows', () {
    test('off ignores the window', () {
      const off = BarkPushSchedule(mode: BarkPushScheduleMode.off);
      expect(off.allows(fri(3, 0)), isTrue);
    });

    test('allowlist pushes only inside the window', () {
      expect(workHours.allows(fri(12, 0)), isTrue);
      expect(workHours.allows(fri(20, 0)), isFalse);
      expect(workHours.allows(DateTime(2026, 10, 31, 12)), isFalse);
    });

    test('blocklist suppresses only inside the window', () {
      final block = workHours.copyWith(mode: BarkPushScheduleMode.block);
      expect(block.allows(fri(12, 0)), isFalse);
      expect(block.allows(fri(20, 0)), isTrue);
      expect(block.allows(DateTime(2026, 10, 31, 12)), isTrue);
    });
  });

  test('json round-trip keeps mode, days and minutes', () {
    final json = workHours.toJson();
    expect(json['days'], [DateTime.monday, DateTime.friday]);
    final restored = BarkPushSchedule.fromJson(json);
    expect(restored, workHours);
  });

  test('json tolerates junk', () {
    expect(BarkPushSchedule.fromJson(null), const BarkPushSchedule());
    expect(BarkPushSchedule.fromJson('nope'), const BarkPushSchedule());
    final schedule = BarkPushSchedule.fromJson({
      'mode': 'nonsense',
      'days': [0, 9, 'monday', 3],
      'startMinute': 5000,
      'endMinute': -1,
    });
    expect(schedule.mode, BarkPushScheduleMode.off);
    expect(schedule.days, {3});
    expect(schedule.startMinute, 9 * 60);
    expect(schedule.endMinute, 18 * 60);
  });

  test('BarkPushSettings carries the schedule through json', () {
    const settings = BarkPushSettings(
      mobileInputOnly: false,
      schedule: workHours,
    );
    final restored = BarkPushSettings.fromJson(settings.toJson());
    expect(restored, settings);
    expect(restored.schedule.mode, BarkPushScheduleMode.allow);
    // Older blobs have no schedule at all: off, never a surprise filter.
    expect(
      BarkPushSettings.fromJson(const {'mode': 'always'}).schedule.isActive,
      isFalse,
    );
  });
}