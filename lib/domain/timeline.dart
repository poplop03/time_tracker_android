import 'models.dart';

/// Builds the Today timeline: entry rows in chronological order, with a gap row
/// wherever the untracked stretch between two blocks reaches [minGap].
///
/// Overlapping blocks never produce a gap — the running "cursor" only ever
/// moves forward.
List<TimelineRow> buildTimeline(
  List<TrackedBlock> blocks, {
  Duration minGap = const Duration(minutes: 10),
}) {
  if (blocks.isEmpty) return const <TimelineRow>[];

  final List<TrackedBlock> sorted = List<TrackedBlock>.of(blocks)
    ..sort((TrackedBlock a, TrackedBlock b) {
      final int byStart = a.startedAt.compareTo(b.startedAt);
      return byStart != 0 ? byStart : a.id.compareTo(b.id);
    });

  final List<TimelineRow> rows = <TimelineRow>[];
  DateTime? cursor;

  for (final TrackedBlock block in sorted) {
    if (cursor != null && block.startedAt.isAfter(cursor)) {
      final Duration gap = block.startedAt.difference(cursor);
      if (gap >= minGap) {
        rows.add(TimelineGap(start: cursor, end: block.startedAt));
      }
    }
    rows.add(TimelineEntry(block));

    final DateTime? end = block.endedAt;
    if (end == null) {
      // A running block owns the rest of the timeline; nothing can follow it.
      cursor = null;
      continue;
    }
    if (cursor == null || end.isAfter(cursor)) cursor = end;
  }

  return rows;
}
