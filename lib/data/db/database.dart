import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Free-text activity names, optionally bucketed into a user-typed group.
@DataClassName('ActivityRow')
class Activities extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get groupName => text().nullable()();
  IntColumn get colorSeed => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[];
}

/// A tracked stretch of time. `endedAt == null` means it is running right now;
/// at most one such row may exist (enforced in the repository).
@DataClassName('BlockRow')
class Blocks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get activityId =>
      integer().references(Activities, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get calendarEventId => text().nullable()();
  BoolColumn get syncDirty => boolean().withDefault(const Constant(true))();
}

@DriftDatabase(tables: <Type>[Activities, Blocks])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'tally'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
          await _createIndexes();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          // Schema 1 is the first shipped version. Future migrations append
          // here; user data is never wiped.
          await _createIndexes();
        },
        beforeOpen: (OpeningDetails details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _createIndexes() async {
    await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS activities_name_nocase '
        'ON activities (name COLLATE NOCASE)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS blocks_started_at ON blocks (started_at)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS blocks_activity_id ON blocks (activity_id)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS blocks_sync_dirty ON blocks (sync_dirty)');
  }
}
