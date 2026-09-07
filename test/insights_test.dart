import 'package:flutter_test/flutter_test.dart';
import 'package:tally/domain/insights.dart';
import 'package:tally/domain/models.dart';

TrackedBlock block(int id, DateTime start, Duration length) => TrackedBlock(
      id: id,
      activityId: id,
      activityName: 'a$id',
      groupName: null,
      colorSeed: id,
      startedAt: start,
      endedAt: start.add(length),
    );

final DateTime _now = DateTime(2026, 9, 7, 18);

void main() {
  test('an empty history is honest rather than zero-divided', () {
    final InsightSet insights = buildInsights(const <TrackedBlock>[], _now);
    expect(insights.daysWithData, 0);
    expect(insights.averageTrackedDay, Duration.zero);
    expect(insights.untrackedShare, 100);
    expect(insights.byHour, hasLength(24));
    expect(insights.byHour.every((Duration d) => d == Duration.zero), isTrue);
  });

  test('averages across the days that actually have data', () {
    final InsightSet insights = buildInsights(<TrackedBlock>[
      block(1, DateTime(2026, 9, 5, 9), const Duration(hours: 4)),
      block(2, DateTime(2026, 9, 7, 9), const Duration(hours: 2)),
    ], _now);

    expect(insights.daysWithData, 2);
    expect(insights.averageTrackedDay, const Duration(hours: 3));
  });

  test('touching blocks merge into one unbroken stretch', () {
    final InsightSet insights = buildInsights(<TrackedBlock>[
      block(1, DateTime(2026, 9, 7, 9), const Duration(hours: 1)),
      block(2, DateTime(2026, 9, 7, 10), const Duration(hours: 1)),
      block(3, DateTime(2026, 9, 7, 14), const Duration(minutes: 30)),
    ], _now);

    expect(insights.longestStretch, const Duration(hours: 2));
    expect(insights.longestStretchDay, DateTime(2026, 9, 7));
  });

  test('a real break splits the stretch', () {
    final InsightSet insights = buildInsights(<TrackedBlock>[
      block(1, DateTime(2026, 9, 7, 9), const Duration(hours: 1)),
      block(2, DateTime(2026, 9, 7, 11), const Duration(minutes: 30)),
    ], _now);
    expect(insights.longestStretch, const Duration(hours: 1));
  });

  test('a block is spread across every hour it spans', () {
    final InsightSet insights = buildInsights(<TrackedBlock>[
      block(1, DateTime(2026, 9, 7, 9, 30), const Duration(hours: 2)),
    ], _now);

    expect(insights.byHour[9], const Duration(minutes: 30));
    expect(insights.byHour[10], const Duration(hours: 1));
    expect(insights.byHour[11], const Duration(minutes: 30));
    expect(insights.byHour[8], Duration.zero);
  });

  test('untracked share is measured against a 16-hour waking day', () {
    final InsightSet insights = buildInsights(<TrackedBlock>[
      block(1, DateTime(2026, 9, 7, 8), const Duration(hours: 8)),
    ], _now);
    expect(insights.untrackedShare, 50);
  });

  test('untracked share never goes below zero on an over-full day', () {
    final InsightSet insights = buildInsights(<TrackedBlock>[
      block(1, DateTime(2026, 9, 7, 0), const Duration(hours: 20)),
    ], _now);
    expect(insights.untrackedShare, 0);
  });

  test('a running block counts up to the supplied clock', () {
    final InsightSet insights = buildInsights(<TrackedBlock>[
      TrackedBlock(
        id: 1,
        activityId: 1,
        activityName: 'live',
        groupName: null,
        colorSeed: 1,
        startedAt: _now.subtract(const Duration(hours: 1)),
      ),
    ], _now);
    expect(insights.averageTrackedDay, const Duration(hours: 1));
  });
}
