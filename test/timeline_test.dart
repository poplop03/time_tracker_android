import 'package:flutter_test/flutter_test.dart';
import 'package:tally/domain/models.dart';
import 'package:tally/domain/timeline.dart';

TrackedBlock block(int id, int startHour, int startMinute, int? endHour,
    [int endMinute = 0]) {
  return TrackedBlock(
    id: id,
    activityId: id,
    activityName: 'Block $id',
    groupName: null,
    colorSeed: id,
    startedAt: DateTime(2026, 9, 7, startHour, startMinute),
    endedAt: endHour == null ? null : DateTime(2026, 9, 7, endHour, endMinute),
  );
}

void main() {
  test('an empty day has no rows', () {
    expect(buildTimeline(const <TrackedBlock>[]), isEmpty);
  });

  test('emits entries in chronological order regardless of input order', () {
    final List<TimelineRow> rows = buildTimeline(<TrackedBlock>[
      block(2, 11, 0, 11, 30),
      block(1, 9, 0, 9, 30),
    ]);
    expect(rows.whereType<TimelineEntry>().map((TimelineEntry e) => e.block.id),
        <int>[1, 2]);
  });

  test('inserts a gap row when the untracked stretch reaches the minimum', () {
    final List<TimelineRow> rows = buildTimeline(<TrackedBlock>[
      block(1, 9, 0, 9, 30),
      block(2, 10, 0, 10, 30),
    ]);
    expect(rows.length, 3);
    expect(rows[1], isA<TimelineGap>());
    final TimelineGap gap = rows[1] as TimelineGap;
    expect(gap.duration, const Duration(minutes: 30));
  });

  test('ignores gaps below the threshold', () {
    final List<TimelineRow> rows = buildTimeline(<TrackedBlock>[
      block(1, 9, 0, 9, 30),
      block(2, 9, 35, 10, 0),
    ]);
    expect(rows.whereType<TimelineGap>(), isEmpty);
    expect(rows.length, 2);
  });

  test('the threshold is inclusive', () {
    final List<TimelineRow> rows = buildTimeline(<TrackedBlock>[
      block(1, 9, 0, 9, 30),
      block(2, 9, 40, 10, 0),
    ]);
    expect(rows.whereType<TimelineGap>(), hasLength(1));
  });

  test('overlapping blocks never produce a gap', () {
    final List<TimelineRow> rows = buildTimeline(<TrackedBlock>[
      block(1, 9, 0, 11, 0),
      block(2, 9, 30, 10, 0),
      block(3, 11, 0, 11, 30),
    ]);
    expect(rows.whereType<TimelineGap>(), isEmpty);
    expect(rows.whereType<TimelineEntry>(), hasLength(3));
  });

  test('a running block ends the timeline', () {
    final List<TimelineRow> rows = buildTimeline(<TrackedBlock>[
      block(1, 9, 0, 9, 30),
      block(2, 14, 0, null),
    ]);
    expect(rows.length, 3);
    expect(rows.last, isA<TimelineEntry>());
    expect((rows.last as TimelineEntry).block.isRunning, isTrue);
  });

  test('honours a custom minimum gap', () {
    final List<TimelineRow> rows = buildTimeline(
      <TrackedBlock>[block(1, 9, 0, 9, 30), block(2, 9, 35, 10, 0)],
      minGap: const Duration(minutes: 5),
    );
    expect(rows.whereType<TimelineGap>(), hasLength(1));
  });
}
