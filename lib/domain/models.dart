import 'package:flutter/foundation.dart';

/// The catch-all bucket for activities the user has not grouped.
const String kUngrouped = 'Ungrouped';

String normalizeGroup(String? raw) {
  final String v = (raw ?? '').trim();
  return v.isEmpty ? kUngrouped : v;
}

/// A block joined with the activity it belongs to. Plain data so the pure
/// functions below stay free of the database layer.
@immutable
class TrackedBlock {
  const TrackedBlock({
    required this.id,
    required this.activityId,
    required this.activityName,
    required this.groupName,
    required this.colorSeed,
    required this.startedAt,
    this.endedAt,
    this.note,
    this.calendarEventId,
    this.syncDirty = true,
  });

  final int id;
  final int activityId;
  final String activityName;
  final String? groupName;
  final int colorSeed;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? note;
  final String? calendarEventId;
  final bool syncDirty;

  bool get isRunning => endedAt == null;

  String get group => normalizeGroup(groupName);

  bool get isSynced => calendarEventId != null && !syncDirty;

  /// Elapsed time, measured against [now] while the block is still running.
  Duration durationAt(DateTime now) {
    final DateTime end = endedAt ?? now;
    final Duration d = end.difference(startedAt);
    return d.isNegative ? Duration.zero : d;
  }

  Duration get duration => endedAt == null
      ? Duration.zero
      : endedAt!.difference(startedAt).abs();
}

/// One activity plus its rolled-up totals, for the Names screen.
@immutable
class ActivitySummary {
  const ActivitySummary({
    required this.id,
    required this.name,
    required this.groupName,
    required this.colorSeed,
    required this.total,
    required this.blockCount,
  });

  final int id;
  final String name;
  final String? groupName;
  final int colorSeed;
  final Duration total;
  final int blockCount;

  String get group => normalizeGroup(groupName);
}

/// A row in the Today timeline: either a tracked entry or an untracked gap.
@immutable
sealed class TimelineRow {
  const TimelineRow();
}

@immutable
class TimelineEntry extends TimelineRow {
  const TimelineEntry(this.block);
  final TrackedBlock block;
}

@immutable
class TimelineGap extends TimelineRow {
  const TimelineGap({required this.start, required this.end});
  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);
}

/// One wedge of the Stats donut.
@immutable
class GroupSlice {
  const GroupSlice({
    required this.group,
    required this.total,
    required this.percent,
    required this.colorSeed,
  });

  final String group;
  final Duration total;

  /// 0–100, rounded so that a breakdown's percents sum to exactly 100.
  final int percent;
  final int colorSeed;
}

/// A day's total, for the 7-day bar chart.
@immutable
class DayTotal {
  const DayTotal({required this.day, required this.total});
  final DateTime day;
  final Duration total;
}

/// Everything the Insights screen shows, derived in one pass.
@immutable
class InsightSet {
  const InsightSet({
    required this.averageTrackedDay,
    required this.longestStretch,
    required this.longestStretchDay,
    required this.untrackedShare,
    required this.byHour,
    required this.observation,
    required this.daysWithData,
  });

  final Duration averageTrackedDay;
  final Duration longestStretch;
  final DateTime? longestStretchDay;

  /// 0–100 share of waking hours (16h/day) with nothing tracked.
  final int untrackedShare;

  /// 24 entries, index == hour of day, value == total tracked in that hour.
  final List<Duration> byHour;
  final String observation;
  final int daysWithData;
}

/// A calendar event the user has not yet accepted as a block.
@immutable
class PulledSuggestion {
  const PulledSuggestion({
    required this.eventId,
    required this.title,
    required this.start,
    required this.end,
  });

  final String eventId;
  final String title;
  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);
}
