import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/bark_push_schedule.dart';
import '../../utils/ui/app_keys.dart';

/// Weekday + time window editor for the Bark push channel.
///
/// Three states: off (no filtering), allowlist (push only inside the window) and
/// blocklist (suppress inside it). Days use ISO weekdays 1–7 so they line up with
/// [DateTime.weekday]; the chip labels come from [MaterialLocalizations] and are
/// already ordered for the active locale.
class BarkPushScheduleEditor extends StatelessWidget {
  const BarkPushScheduleEditor({
    required this.schedule,
    required this.onChanged,
    super.key,
  });

  final BarkPushSchedule schedule;
  final ValueChanged<BarkPushSchedule> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final active = schedule.isActive;
    return TpPreferenceStack(
      title: l10n.barkPushScheduleTitle,
      subtitle: l10n.barkPushScheduleDescription,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TpSegmentedPicker<BarkPushScheduleMode>(
            key: AppKeys.barkPushScheduleMode,
            alignment: Alignment.centerLeft,
            segments: [
              TpSegmentedOption<BarkPushScheduleMode>(
                value: BarkPushScheduleMode.off,
                label: l10n.barkPushScheduleModeOff,
                icon: Icons.event_available_outlined,
              ),
              TpSegmentedOption<BarkPushScheduleMode>(
                value: BarkPushScheduleMode.allow,
                label: l10n.barkPushScheduleModeAllow,
                icon: Icons.filter_alt_outlined,
              ),
              TpSegmentedOption<BarkPushScheduleMode>(
                value: BarkPushScheduleMode.block,
                label: l10n.barkPushScheduleModeBlock,
                icon: Icons.block_outlined,
              ),
            ],
            selected: schedule.mode,
            onChanged: (mode) => onChanged(schedule.copyWith(mode: mode)),
          ),
          if (active) ...[
            const SizedBox(height: 12),
            _ScheduleCaption(text: l10n.barkPushScheduleDaysLabel),
            const SizedBox(height: 6),
            _DayChips(schedule: schedule, onChanged: onChanged),
            const SizedBox(height: 12),
            _ScheduleCaption(text: l10n.barkPushScheduleTimeLabel),
            const SizedBox(height: 6),
            Row(
              children: [
                _TimeButton(
                  buttonKey: AppKeys.barkPushScheduleStart,
                  label: l10n.barkPushScheduleStartTime,
                  minuteOfDay: schedule.startMinute,
                  onChanged: (minute) =>
                      onChanged(schedule.copyWith(startMinute: minute)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '–',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                _TimeButton(
                  buttonKey: AppKeys.barkPushScheduleEnd,
                  label: l10n.barkPushScheduleEndTime,
                  minuteOfDay: schedule.endMinute,
                  onChanged: (minute) =>
                      onChanged(schedule.copyWith(endMinute: minute)),
                ),
              ],
            ),
            if (schedule.startMinute > schedule.endMinute) ...[
              const SizedBox(height: 8),
              _ScheduleCaption(
                text: l10n.barkPushScheduleOvernightHint,
                icon: Icons.nights_stay_outlined,
              ),
            ],
          ],
        ],
      ),
      showDividerBelow: true,
    );
  }
}

class _ScheduleCaption extends StatelessWidget {
  const _ScheduleCaption({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            text,
            style: TpTextStyles.of(context).xsColored(cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _DayChips extends StatelessWidget {
  const _DayChips({required this.schedule, required this.onChanged});

  final BarkPushSchedule schedule;
  final ValueChanged<BarkPushSchedule> onChanged;

  /// Short weekday names in locale order, paired with their ISO weekday.
  ///
  /// [MaterialLocalizations] only exposes single-letter [narrowWeekdays] ("T"
  /// twice, "S" twice), so the labels come from intl. Monday first: a work-week
  /// window reads that way in zh and en alike.
  List<(int, String)> _weekdays(BuildContext context) {
    final format = DateFormat.E(Localizations.localeOf(context).toLanguageTag());
    // 2024-01-01 was a Monday; day arithmetic on the constructor (not Duration)
    // keeps this DST-proof.
    return [
      for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++)
        (weekday, format.format(DateTime(2024, 1, weekday))),
    ];
  }

  void _toggle(int weekday) {
    final days = Set<int>.from(schedule.days);
    if (!days.remove(weekday)) {
      days.add(weekday);
    } else if (days.isEmpty) {
      // The last selected day stays: an empty set would silently mean "every
      // day", which is the opposite of what the user just asked for.
      return;
    }
    onChanged(schedule.copyWith(days: days));
  }

  @override
  Widget build(BuildContext context) {
    final activeDays = schedule.days.isEmpty
        ? BarkPushSchedule.allWeekdays
        : schedule.days;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (weekday, label) in _weekdays(context))
          FilterChip(
            key: AppKeys.barkPushScheduleDay(weekday),
            label: Text(label),
            selected: activeDays.contains(weekday),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onSelected: (_) => _toggle(weekday),
          ),
      ],
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.buttonKey,
    required this.label,
    required this.minuteOfDay,
    required this.onChanged,
  });

  final Key buttonKey;
  final String label;
  final int minuteOfDay;
  final ValueChanged<int> onChanged;

  String _format(BuildContext context) => MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(
    TimeOfDay(hour: minuteOfDay ~/ 60, minute: minuteOfDay % 60),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );

  Future<void> _pick(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minuteOfDay ~/ 60, minute: minuteOfDay % 60),
      helpText: label,
      builder: (pickerContext, child) => MediaQuery(
        data: MediaQuery.of(pickerContext).copyWith(
          alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null) return;
    onChanged(picked.hour * 60 + picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TpButton(
      key: buttonKey,
      variant: TpButtonVariant.secondary,
      onPressed: () => unawaited(_pick(context)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 15, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(_format(context)),
        ],
      ),
    );
  }
}