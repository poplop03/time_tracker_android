import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tally/data/db/database.dart';
import 'package:tally/data/repositories/activity_repository.dart';
import 'package:tally/data/repositories/tracking_repository.dart';
import 'package:tally/domain/models.dart';

void main() {
  late AppDatabase db;
  late ActivityRepository activities;
  late TrackingRepository blocks;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    activities = ActivityRepository(db);
    blocks = TrackingRepository(db, activities);
  });

  tearDown(() async => db.close());

  group('activities', () {
    test('duplicate names are rejected, case-insensitively', () async {
      expect(await activities.addActivity('Deep work'), isTrue);
      expect(await activities.addActivity('deep WORK'), isFalse);
      expect(await activities.watchSummaries().first, hasLength(1));
    });

    test('getOrCreate reuses an existing name rather than duplicating', () async {
      final int first = (await activities.getOrCreate('Reading')).id;
      final int second = (await activities.getOrCreate('reading')).id;
      expect(second, first);
    });

    test('grouping and ungrouping move the group string', () async {
      await activities.addActivity('Email');
      await activities.addActivity('Standup');
      final List<ActivitySummary> all = await activities.watchSummaries().first;
      await activities.assignGroup(
          all.map((ActivitySummary a) => a.id).toList(), 'Work');

      expect(await activities.watchGroups().first, <String>['Work']);

      await activities.ungroup('Work');
      expect(await activities.watchGroups().first, isEmpty);
      final List<ActivitySummary> after = await activities.watchSummaries().first;
      expect(after.every((ActivitySummary a) => a.group == kUngrouped), isTrue);
    });

    test('summaries roll up totals and counts', () async {
      final DateTime base = DateTime(2026, 9, 7, 9);
      await blocks.addRetroactive(
          activityName: 'Code',
          start: base,
          end: base.add(const Duration(hours: 1)));
      await blocks.addRetroactive(
          activityName: 'Code',
          start: base.add(const Duration(hours: 2)),
          end: base.add(const Duration(hours: 3, minutes: 30)));

      final ActivitySummary summary =
          (await activities.watchSummaries().first).single;
      expect(summary.blockCount, 2);
      expect(summary.total, const Duration(hours: 2, minutes: 30));
    });
  });

  group('the running block', () {
    test('start creates exactly one open block', () async {
      await blocks.start('Deep work');
      final TrackedBlock? running = await blocks.currentRunning();
      expect(running, isNotNull);
      expect(running!.isRunning, isTrue);
      expect(running.activityName, 'Deep work');
    });

    test('starting again closes the previous block', () async {
      await blocks.start('First');
      await blocks.start('Second');

      final TrackedBlock? running = await blocks.currentRunning();
      expect(running!.activityName, 'Second');

      final List<TrackedBlock> all = await blocks.allBlocks();
      expect(all, hasLength(2));
      expect(all.where((TrackedBlock b) => b.isRunning), hasLength(1));
    });

    test('stop closes the block and marks it dirty', () async {
      final TrackedBlock started = await blocks.start('Deep work');
      final DateTime end = started.startedAt.add(const Duration(minutes: 40));
      final TrackedBlock? stopped = await blocks.stop(at: end);

      expect(stopped!.endedAt, end);
      expect(await blocks.currentRunning(), isNull);
      expect(await blocks.dirtyBlocks(), hasLength(1));
      expect(await blocks.watchPendingCount().first, 1);
    });

    test('stop never produces a negative duration', () async {
      final TrackedBlock started = await blocks.start('Deep work');
      final TrackedBlock? stopped = await blocks
          .stop(at: started.startedAt.subtract(const Duration(hours: 1)));
      expect(stopped!.endedAt, started.startedAt);
    });

    test('stop with nothing running is a no-op', () async {
      expect(await blocks.stop(), isNull);
    });
  });

  group('retroactive blocks', () {
    final DateTime base = DateTime(2026, 9, 7, 9);

    Future<void> seed(int fromHour, int toHour) => blocks.addRetroactive(
          activityName: 'Existing',
          start: base.add(Duration(hours: fromHour)),
          end: base.add(Duration(hours: toHour)),
        );

    test('a clean insert touches nothing else', () async {
      await seed(0, 1);
      final BlockPlacement result = await blocks.addRetroactive(
        activityName: 'New',
        start: base.add(const Duration(hours: 2)),
        end: base.add(const Duration(hours: 3)),
      );
      expect(result.trimmed, 0);
      expect(result.removed, 0);
      expect(await blocks.allBlocks(), hasLength(2));
    });

    test('a block fully inside an existing one is rejected', () async {
      await seed(0, 3);
      expect(
        () => blocks.addRetroactive(
          activityName: 'New',
          start: base.add(const Duration(hours: 1)),
          end: base.add(const Duration(hours: 2)),
        ),
        throwsA(isA<OverlapRejected>()),
      );
      expect(await blocks.allBlocks(), hasLength(1));
    });

    test('an earlier overlapping block is trimmed, not deleted', () async {
      await seed(0, 2);
      final BlockPlacement result = await blocks.addRetroactive(
        activityName: 'New',
        start: base.add(const Duration(hours: 1)),
        end: base.add(const Duration(hours: 3)),
      );
      expect(result.trimmed, 1);

      final List<TrackedBlock> all = await blocks.allBlocks();
      expect(all, hasLength(2));
      final TrackedBlock existing =
          all.firstWhere((TrackedBlock b) => b.activityName == 'Existing');
      expect(existing.endedAt, base.add(const Duration(hours: 1)));
    });

    test('a later overlapping block has its start pushed back', () async {
      await seed(2, 4);
      await blocks.addRetroactive(
        activityName: 'New',
        start: base.add(const Duration(hours: 1)),
        end: base.add(const Duration(hours: 3)),
      );
      final TrackedBlock existing = (await blocks.allBlocks())
          .firstWhere((TrackedBlock b) => b.activityName == 'Existing');
      expect(existing.startedAt, base.add(const Duration(hours: 3)));
    });

    test('a fully covered block is replaced', () async {
      await seed(1, 2);
      final BlockPlacement result = await blocks.addRetroactive(
        activityName: 'New',
        start: base,
        end: base.add(const Duration(hours: 3)),
      );
      expect(result.removed, 1);
      expect(await blocks.allBlocks(), hasLength(1));
    });

    test('overlapping the running timer is rejected', () async {
      await blocks.start('Live');
      expect(
        () => blocks.addRetroactive(
          activityName: 'New',
          start: DateTime.now().subtract(const Duration(minutes: 10)),
          end: DateTime.now().add(const Duration(minutes: 10)),
        ),
        throwsA(isA<OverlapRejected>()),
      );
    });

    test('a zero-length block is rejected', () async {
      expect(
        () => blocks.addRetroactive(
            activityName: 'New', start: base, end: base),
        throwsA(isA<OverlapRejected>()),
      );
    });
  });

  group('sync bookkeeping', () {
    test('marking synced clears the dirty flag and stores the event id',
        () async {
      final DateTime base = DateTime(2026, 9, 7, 9);
      await blocks.addRetroactive(
          activityName: 'Code',
          start: base,
          end: base.add(const Duration(hours: 1)));

      final TrackedBlock dirty = (await blocks.dirtyBlocks()).single;
      await blocks.markSynced(dirty.id, 'evt-1');

      expect(await blocks.dirtyBlocks(), isEmpty);
      final TrackedBlock synced = (await blocks.allBlocks()).single;
      expect(synced.calendarEventId, 'evt-1');
      expect(synced.isSynced, isTrue);
      expect(await blocks.hasEventId('evt-1'), isTrue);
    });

    test('a running block is never queued for sync', () async {
      await blocks.start('Live');
      expect(await blocks.dirtyBlocks(), isEmpty);
      expect(await blocks.watchPendingCount().first, 0);
    });

    test('an accepted suggestion lands already synced', () async {
      final DateTime base = DateTime(2026, 9, 7, 9);
      await blocks.acceptSuggestion(
        title: 'Design review',
        start: base,
        end: base.add(const Duration(minutes: 30)),
        eventId: 'evt-9',
      );
      final TrackedBlock block = (await blocks.allBlocks()).single;
      expect(block.activityName, 'Design review');
      expect(block.syncDirty, isFalse);
      expect(await blocks.dirtyBlocks(), isEmpty);
    });
  });

  group('day queries', () {
    test('watchDay only returns blocks starting that day', () async {
      final DateTime today = DateTime(2026, 9, 7, 10);
      final DateTime yesterday = DateTime(2026, 9, 6, 10);
      await blocks.addRetroactive(
          activityName: 'Today',
          start: today,
          end: today.add(const Duration(hours: 1)));
      await blocks.addRetroactive(
          activityName: 'Yesterday',
          start: yesterday,
          end: yesterday.add(const Duration(hours: 1)));

      final List<TrackedBlock> day = await blocks.watchDay(today).first;
      expect(day, hasLength(1));
      expect(day.single.activityName, 'Today');
    });
  });
}
