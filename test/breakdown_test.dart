import 'package:flutter_test/flutter_test.dart';
import 'package:tally/domain/breakdown.dart';
import 'package:tally/domain/models.dart';

ActivitySummary activity(int id, String name, String? group) => ActivitySummary(
      id: id,
      name: name,
      groupName: group,
      colorSeed: id,
      total: Duration.zero,
      blockCount: 0,
    );

TrackedBlock blockOf(int id, int activityId, Duration length) => TrackedBlock(
      id: id,
      activityId: activityId,
      activityName: 'a$activityId',
      groupName: null,
      colorSeed: activityId,
      startedAt: DateTime(2026, 9, 7, 9),
      endedAt: DateTime(2026, 9, 7, 9).add(length),
    );

void main() {
  test('an empty week has no slices', () {
    expect(groupBreakdown(const <ActivitySummary>[], const <TrackedBlock>[]),
        isEmpty);
  });

  test('sums by group and sorts longest first', () {
    final List<GroupSlice> slices = groupBreakdown(
      <ActivitySummary>[
        activity(1, 'Code', 'Work'),
        activity(2, 'Email', 'Work'),
        activity(3, 'Netflix', 'Entertainment'),
      ],
      <TrackedBlock>[
        blockOf(1, 1, const Duration(hours: 2)),
        blockOf(2, 2, const Duration(hours: 1)),
        blockOf(3, 3, const Duration(hours: 1)),
      ],
    );

    expect(slices.map((GroupSlice s) => s.group), <String>['Work', 'Entertainment']);
    expect(slices.first.total, const Duration(hours: 3));
  });

  test('percents always sum to 100', () {
    final List<GroupSlice> slices = groupBreakdown(
      <ActivitySummary>[
        activity(1, 'a', 'A'),
        activity(2, 'b', 'B'),
        activity(3, 'c', 'C'),
      ],
      <TrackedBlock>[
        blockOf(1, 1, const Duration(minutes: 20)),
        blockOf(2, 2, const Duration(minutes: 20)),
        blockOf(3, 3, const Duration(minutes: 20)),
      ],
    );

    expect(slices.fold(0, (int sum, GroupSlice s) => sum + s.percent), 100);
  });

  test('ungrouped activities land in the catch-all bucket', () {
    final List<GroupSlice> slices = groupBreakdown(
      <ActivitySummary>[activity(1, 'Reading', null)],
      <TrackedBlock>[blockOf(1, 1, const Duration(hours: 1))],
    );
    expect(slices.single.group, kUngrouped);
    expect(slices.single.percent, 100);
  });

  test('regrouping moves the time without changing the total', () {
    final List<TrackedBlock> blocks = <TrackedBlock>[
      blockOf(1, 1, const Duration(hours: 1)),
      blockOf(2, 2, const Duration(hours: 1)),
    ];
    final List<GroupSlice> before = groupBreakdown(
      <ActivitySummary>[activity(1, 'a', 'A'), activity(2, 'b', 'B')],
      blocks,
    );
    final List<GroupSlice> after = groupBreakdown(
      <ActivitySummary>[activity(1, 'a', 'A'), activity(2, 'b', 'A')],
      blocks,
    );

    expect(before, hasLength(2));
    expect(after, hasLength(1));
    expect(after.single.total, const Duration(hours: 2));
    expect(after.single.percent, 100);
  });

  test('running blocks count against the supplied clock', () {
    final DateTime start = DateTime(2026, 9, 7, 9);
    final List<GroupSlice> slices = groupBreakdown(
      <ActivitySummary>[activity(1, 'a', 'A')],
      <TrackedBlock>[
        TrackedBlock(
          id: 1,
          activityId: 1,
          activityName: 'a',
          groupName: null,
          colorSeed: 1,
          startedAt: start,
        ),
      ],
      now: start.add(const Duration(minutes: 30)),
    );
    expect(slices.single.total, const Duration(minutes: 30));
  });
}
