import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tally/features/sync/csv_export.dart';
import 'package:tally/features/sync/csv_import.dart';
import 'package:tally/data/db/database.dart';
import 'package:tally/data/repositories/activity_repository.dart';
import 'package:tally/data/repositories/tracking_repository.dart';
import 'package:tally/domain/import.dart';
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

  group('editing a block', () {
    final DateTime base = DateTime(2026, 9, 7, 9);

    Future<TrackedBlock> seed(String name, int fromHour, int toHour) async {
      await blocks.addRetroactive(
        activityName: name,
        start: base.add(Duration(hours: fromHour)),
        end: base.add(Duration(hours: toHour)),
      );
      return (await blocks.allBlocks())
          .lastWhere((TrackedBlock b) => b.activityName == name);
    }

    test('changes times and description, and queues a re-sync', () async {
      final TrackedBlock block = await seed('Code', 0, 1);
      await blocks.markSynced(block.id, 'evt-1');

      await blocks.editBlock(
        id: block.id,
        start: base.add(const Duration(minutes: 15)),
        end: base.add(const Duration(hours: 2)),
        note: '  Refactored the timeline  ',
      );

      final TrackedBlock edited = (await blocks.allBlocks()).single;
      expect(edited.startedAt, base.add(const Duration(minutes: 15)));
      expect(edited.endedAt, base.add(const Duration(hours: 2)));
      expect(edited.note, 'Refactored the timeline');
      expect(edited.syncDirty, isTrue);
      // The event id stays, so the next push updates the event in place.
      expect(edited.calendarEventId, 'evt-1');
    });

    test('clearing the description stores it as absent', () async {
      final TrackedBlock block = await seed('Code', 0, 1);
      await blocks.editBlock(
          id: block.id, start: block.startedAt, end: block.endedAt, note: 'x');
      await blocks.editBlock(
          id: block.id, start: block.startedAt, end: block.endedAt, note: '  ');
      expect((await blocks.allBlocks()).single.note, isNull);
    });

    test('a block does not collide with its own old span', () async {
      final TrackedBlock block = await seed('Code', 0, 3);
      final BlockPlacement result = await blocks.editBlock(
        id: block.id,
        start: base.add(const Duration(hours: 1)),
        end: base.add(const Duration(hours: 2)),
      );
      expect(result.trimmed, 0);
      expect(result.removed, 0);
    });

    test('stretching over a neighbour trims it', () async {
      final TrackedBlock block = await seed('Code', 0, 1);
      await seed('Email', 1, 3);

      final BlockPlacement result = await blocks.editBlock(
        id: block.id,
        start: base,
        end: base.add(const Duration(hours: 2)),
      );
      expect(result.trimmed, 1);
      final TrackedBlock email = (await blocks.allBlocks())
          .firstWhere((TrackedBlock b) => b.activityName == 'Email');
      expect(email.startedAt, base.add(const Duration(hours: 2)));
    });

    test('moving inside another block is refused and writes nothing', () async {
      await seed('Meeting', 0, 4);
      final TrackedBlock block = await seed('Code', 5, 6);

      await expectLater(
        blocks.editBlock(
          id: block.id,
          start: base.add(const Duration(hours: 1)),
          end: base.add(const Duration(hours: 2)),
        ),
        throwsA(isA<OverlapRejected>()),
      );
      final TrackedBlock unchanged = (await blocks.allBlocks())
          .firstWhere((TrackedBlock b) => b.activityName == 'Code');
      expect(unchanged.startedAt, base.add(const Duration(hours: 5)));
    });

    test('an end before the start is refused', () async {
      final TrackedBlock block = await seed('Code', 1, 2);
      await expectLater(
        blocks.editBlock(id: block.id, start: block.endedAt!, end: block.startedAt),
        throwsA(isA<OverlapRejected>()),
      );
    });

    test('a running block only takes a description', () async {
      final TrackedBlock running = await blocks.start('Live');
      await blocks.editBlock(
        id: running.id,
        start: running.startedAt.subtract(const Duration(hours: 3)),
        note: 'Pairing on sync',
      );
      final TrackedBlock after = (await blocks.currentRunning())!;
      expect(after.note, 'Pairing on sync');
      expect(after.startedAt, running.startedAt);
      expect(after.isRunning, isTrue);
    });

    test('a vanished block is reported, not silently ignored', () async {
      await expectLater(
        blocks.editBlock(id: 999, start: base, end: base.add(const Duration(hours: 1))),
        throwsA(isA<OverlapRejected>()),
      );
    });

    test('an activity\'s blocks come newest first and page by limit', () async {
      for (int h = 0; h < 5; h++) {
        await seed('Code', h, h + 1);
      }
      final int id = (await blocks.allBlocks()).first.activityId;

      final List<TrackedBlock> page =
          await blocks.watchActivityBlocks(id, limit: 3).first;
      expect(page, hasLength(3));
      expect(page.first.startedAt, base.add(const Duration(hours: 4)));
      expect(page.last.startedAt, base.add(const Duration(hours: 2)));
    });
  });

  group('importing', () {
    final DateTime base = DateTime(2026, 9, 7, 9);

    ImportRow row(int line, String name, int fromHour, int toHour,
            {String? group, String? note, bool onCalendar = false}) =>
        ImportRow(
          line: line,
          activity: name,
          group: group,
          start: base.add(Duration(hours: fromHour)),
          end: base.add(Duration(hours: toHour)),
          note: note,
          alreadyOnCalendar: onCalendar,
        );

    test('adds rows to an empty database, with groups and descriptions',
        () async {
      final ImportOutcome outcome = await blocks.importBlocks(<ImportRow>[
        row(2, 'Code', 0, 1, group: 'Work', note: 'Parser'),
        row(3, 'Reading', 2, 3, group: 'Ungrouped'),
      ]);

      expect(outcome.added, 2);
      expect(outcome.duplicates, 0);
      expect(outcome.overlapping, 0);
      expect(outcome.firstStart, base);
      expect(outcome.lastEnd, base.add(const Duration(hours: 3)));

      final List<TrackedBlock> all = await blocks.allBlocks();
      expect(all.first.activityName, 'Code');
      expect(all.first.groupName, 'Work');
      expect(all.first.note, 'Parser');
      expect(all.last.groupName, isNull); // "Ungrouped" means no group
    });

    test('importing the same file twice adds nothing the second time',
        () async {
      final List<ImportRow> rows = <ImportRow>[
        row(2, 'Code', 0, 1),
        row(3, 'Email', 1, 2),
      ];
      await blocks.importBlocks(rows);
      final ImportOutcome again = await blocks.importBlocks(rows);

      expect(again.added, 0);
      expect(again.duplicates, 2);
      expect(await blocks.allBlocks(), hasLength(2));
    });

    test('names match regardless of case when spotting duplicates', () async {
      await blocks.importBlocks(<ImportRow>[row(2, 'Code', 0, 1)]);
      final ImportOutcome again =
          await blocks.importBlocks(<ImportRow>[row(2, 'CODE', 0, 1)]);
      expect(again.duplicates, 1);
    });

    test('rows overlapping stored blocks are skipped, and those blocks kept',
        () async {
      await blocks.addRetroactive(
        activityName: 'Meeting',
        start: base.add(const Duration(hours: 1)),
        end: base.add(const Duration(hours: 3)),
      );

      final ImportOutcome outcome = await blocks.importBlocks(<ImportRow>[
        row(2, 'Code', 0, 2),  // runs into the meeting
        row(3, 'Email', 3, 4), // starts as the meeting ends — fine
        row(4, 'Lunch', 2, 5), // starts inside the meeting
      ]);

      expect(outcome.added, 1);
      expect(outcome.overlapLines, <int>[2, 4]);
      final TrackedBlock meeting = (await blocks.allBlocks())
          .firstWhere((TrackedBlock b) => b.activityName == 'Meeting');
      expect(meeting.startedAt, base.add(const Duration(hours: 1)));
      expect(meeting.endedAt, base.add(const Duration(hours: 3)));
    });

    test('rows overlapping each other keep the earlier one', () async {
      final ImportOutcome outcome = await blocks.importBlocks(<ImportRow>[
        row(5, 'Later', 1, 3),
        row(2, 'Earlier', 0, 2),
      ]);
      expect(outcome.added, 1);
      expect(outcome.overlapLines, <int>[5]);
      expect((await blocks.allBlocks()).single.activityName, 'Earlier');
    });

    test("nothing after a running timer's start is imported", () async {
      final TrackedBlock running = await blocks.start('Live');
      final ImportOutcome outcome = await blocks.importBlocks(<ImportRow>[
        ImportRow(
          line: 2,
          activity: 'Code',
          start: running.startedAt.add(const Duration(minutes: 1)),
          end: running.startedAt.add(const Duration(minutes: 30)),
        ),
      ]);
      expect(outcome.added, 0);
      expect(outcome.overlapping, 1);
    });

    test('a preview reports the same outcome but writes nothing', () async {
      await blocks.addRetroactive(
        activityName: 'Meeting',
        start: base,
        end: base.add(const Duration(hours: 1)),
      );
      final List<ImportRow> rows = <ImportRow>[
        row(2, 'Meeting', 0, 1),
        row(3, 'Code', 0, 2),
        row(4, 'Email', 2, 3),
      ];

      final ImportOutcome preview =
          await blocks.importBlocks(rows, dryRun: true);
      expect(await blocks.allBlocks(), hasLength(1));

      final ImportOutcome real = await blocks.importBlocks(rows);
      expect(
        <Object>[preview.added, preview.duplicates, preview.overlapLines],
        <Object>[real.added, real.duplicates, real.overlapLines],
      );
      expect(await blocks.allBlocks(), hasLength(2));
    });

    test('an existing activity keeps the group the user gave it', () async {
      await blocks.addRetroactive(
        activityName: 'Code',
        groupName: 'Side project',
        start: base,
        end: base.add(const Duration(hours: 1)),
      );
      await blocks.importBlocks(<ImportRow>[
        row(2, 'Code', 2, 3, group: 'Work'),
        row(3, 'Brand new', 4, 5, group: 'Work'),
      ]);

      final List<ActivitySummary> summaries =
          await activities.watchSummaries().first;
      expect(
        summaries.firstWhere((ActivitySummary a) => a.name == 'Code').groupName,
        'Side project',
      );
      expect(
        summaries
            .firstWhere((ActivitySummary a) => a.name == 'Brand new')
            .groupName,
        'Work',
      );
    });

    test('blocks already on a calendar are not queued to be pushed again',
        () async {
      await blocks.importBlocks(<ImportRow>[
        row(2, 'Pushed before', 0, 1, onCalendar: true),
        row(3, 'Never pushed', 2, 3),
      ]);
      final List<TrackedBlock> dirty = await blocks.dirtyBlocks();
      expect(dirty.single.activityName, 'Never pushed');
      // The old phone's event id is not carried over.
      expect(
        (await blocks.allBlocks()).every((TrackedBlock b) => b.calendarEventId == null),
        isTrue,
      );
    });

    test('an empty import is a no-op', () async {
      final ImportOutcome outcome = await blocks.importBlocks(<ImportRow>[]);
      expect(outcome.added, 0);
    });

    test('an export imports into a fresh install as the same blocks',
        () async {
      await blocks.addRetroactive(
        activityName: 'Email, then code',
        groupName: 'Work',
        start: base,
        end: base.add(const Duration(hours: 1, minutes: 30)),
        note: 'Wrote "the intro"\nand fixed CI',
      );
      await blocks.addRetroactive(
        activityName: 'Reading',
        start: base.add(const Duration(hours: 3)),
        end: base.add(const Duration(hours: 4)),
      );
      final String csv = CsvExport.buildCsv(await blocks.allBlocks());

      final AppDatabase fresh = AppDatabase.forTesting(NativeDatabase.memory());
      final TrackingRepository restored =
          TrackingRepository(fresh, ActivityRepository(fresh));
      try {
        final ParsedImport parsed =
            readImport(csv, now: DateTime(2026, 9, 11, 18));
        expect(parsed.problems, isEmpty);
        final ImportOutcome outcome = await restored.importBlocks(parsed.rows);
        expect(outcome.added, 2);

        String describe(TrackedBlock b) =>
            '${b.activityName}|${b.groupName}|${b.startedAt}|${b.endedAt}|${b.note}';
        expect(
          (await restored.allBlocks()).map(describe),
          (await blocks.allBlocks()).map(describe),
        );
      } finally {
        await fresh.close();
      }
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
