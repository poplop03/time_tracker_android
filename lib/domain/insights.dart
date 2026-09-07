import '../core/time/day.dart';
import '../core/time/formatting.dart';
import 'models.dart';

/// Waking hours assumed per day when reporting the untracked share.
const Duration kWakingDay = Duration(hours: 16);

/// Two blocks closer together than this count as one unbroken stretch.
const Duration kStretchTolerance = Duration(minutes: 5);

/// Derives every number on the Insights screen from real blocks. Returns an
/// honest empty set when there is nothing to work with.
InsightSet buildInsights(List<TrackedBlock> blocks, DateTime now) {
  final List<TrackedBlock> closed = blocks
      .where((TrackedBlock b) => b.durationAt(now) > Duration.zero)
      .toList()
    ..sort((TrackedBlock a, TrackedBlock b) => a.startedAt.compareTo(b.startedAt));

  final List<Duration> byHour =
      List<Duration>.filled(24, Duration.zero, growable: false);

  if (closed.isEmpty) {
    return InsightSet(
      averageTrackedDay: Duration.zero,
      longestStretch: Duration.zero,
      longestStretchDay: null,
      untrackedShare: 100,
      byHour: byHour,
      observation: 'Track a few blocks and this page fills itself in.',
      daysWithData: 0,
    );
  }

  // Per-day totals.
  final Map<DateTime, Duration> perDay = <DateTime, Duration>{};
  for (final TrackedBlock b in closed) {
    final DateTime day = startOfDay(b.startedAt);
    perDay[day] = (perDay[day] ?? Duration.zero) + b.durationAt(now);
    _spreadOverHours(b, now, byHour);
  }

  final int days = perDay.length;
  final Duration tracked = perDay.values
      .fold(Duration.zero, (Duration sum, Duration d) => sum + d);
  final Duration average = Duration(seconds: tracked.inSeconds ~/ days);

  // Longest unbroken stretch: merge blocks that touch (within tolerance).
  Duration longest = Duration.zero;
  DateTime? longestDay;
  DateTime runStart = closed.first.startedAt;
  DateTime runEnd = closed.first.endedAt ?? now;
  for (int i = 1; i < closed.length; i++) {
    final TrackedBlock b = closed[i];
    final DateTime end = b.endedAt ?? now;
    if (b.startedAt.difference(runEnd) <= kStretchTolerance) {
      if (end.isAfter(runEnd)) runEnd = end;
    } else {
      final Duration run = runEnd.difference(runStart);
      if (run > longest) {
        longest = run;
        longestDay = startOfDay(runStart);
      }
      runStart = b.startedAt;
      runEnd = end;
    }
  }
  final Duration lastRun = runEnd.difference(runStart);
  if (lastRun > longest) {
    longest = lastRun;
    longestDay = startOfDay(runStart);
  }

  final int wakingSeconds = kWakingDay.inSeconds * days;
  final int untrackedSeconds =
      (wakingSeconds - tracked.inSeconds).clamp(0, wakingSeconds);
  final int untrackedShare =
      wakingSeconds == 0 ? 0 : (untrackedSeconds * 100 / wakingSeconds).round();

  return InsightSet(
    averageTrackedDay: average,
    longestStretch: longest,
    longestStretchDay: longestDay,
    untrackedShare: untrackedShare,
    byHour: byHour,
    observation: _observation(byHour, average, untrackedShare),
    daysWithData: days,
  );
}

/// Splits a block across the hour buckets it actually spans.
void _spreadOverHours(TrackedBlock block, DateTime now, List<Duration> byHour) {
  DateTime cursor = block.startedAt;
  final DateTime end = block.endedAt ?? now;
  if (!end.isAfter(cursor)) return;

  while (cursor.isBefore(end)) {
    final DateTime nextHour =
        DateTime(cursor.year, cursor.month, cursor.day, cursor.hour)
            .add(const Duration(hours: 1));
    final DateTime sliceEnd = nextHour.isBefore(end) ? nextHour : end;
    final int hour = cursor.hour;
    byHour[hour] = byHour[hour] + sliceEnd.difference(cursor);
    cursor = sliceEnd;
  }
}

String _observation(List<Duration> byHour, Duration average, int untracked) {
  int peak = 0;
  for (int h = 1; h < 24; h++) {
    if (byHour[h] > byHour[peak]) peak = h;
  }
  if (byHour[peak] == Duration.zero) {
    return 'Not enough tracked time yet to spot a pattern.';
  }
  final String hourLabel = formatClock(DateTime(2000, 1, 1, peak), false)
      .replaceFirst(':00', '');
  if (untracked >= 70) {
    return 'Most of your waking time is still untracked — but when you do '
        'track, $hourLabel is your busiest hour.';
  }
  return 'You do your most tracked work around $hourLabel, and you average '
      '${formatDuration(average)} a day.';
}
