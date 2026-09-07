import 'package:drift/drift.dart';

import '../../domain/models.dart';
import '../db/database.dart';

/// Reads and writes activities and the group string on them. Groups are not a
/// table: renaming one is a bulk update of that string.
class ActivityRepository {
  ActivityRepository(this._db);

  final AppDatabase _db;

  /// Every activity with its rolled-up total and block count, aggregated in
  /// SQL so the blocks table is never pulled into memory.
  Stream<List<ActivitySummary>> watchSummaries() {
    final Expression<int> durationSeconds =
        _db.blocks.endedAt.unixepoch - _db.blocks.startedAt.unixepoch;
    final Expression<int> totalSeconds = durationSeconds.sum();
    final Expression<int> blockCount =
        _db.blocks.id.count(filter: _db.blocks.endedAt.isNotNull());

    final JoinedSelectStatement<HasResultSet, dynamic> query =
        _db.selectOnly(_db.activities).join(<Join<HasResultSet, dynamic>>[
      leftOuterJoin(
          _db.blocks, _db.blocks.activityId.equalsExp(_db.activities.id)),
    ])
          ..addColumns(<Expression<Object>>[
            _db.activities.id,
            _db.activities.name,
            _db.activities.groupName,
            _db.activities.colorSeed,
            totalSeconds,
            blockCount,
          ])
          ..groupBy(<Expression<Object>>[_db.activities.id])
          ..orderBy(<OrderingTerm>[
            OrderingTerm(expression: _db.activities.name.lower()),
          ]);

    return query.watch().map((List<TypedResult> rows) {
      return rows.map((TypedResult row) {
        return ActivitySummary(
          id: row.read(_db.activities.id)!,
          name: row.read(_db.activities.name)!,
          groupName: row.read(_db.activities.groupName),
          colorSeed: row.read(_db.activities.colorSeed) ?? 0,
          total: Duration(seconds: row.read(totalSeconds) ?? 0),
          blockCount: row.read(blockCount) ?? 0,
        );
      }).toList();
    }).distinct(_sameSummaries);
  }

  /// Distinct group names currently in use, alphabetical, without the
  /// catch-all bucket.
  Stream<List<String>> watchGroups() {
    return watchSummaries().map((List<ActivitySummary> list) {
      final Set<String> groups = <String>{
        for (final ActivitySummary a in list)
          if (a.groupName != null && a.groupName!.trim().isNotEmpty)
            a.groupName!.trim(),
      };
      final List<String> out = groups.toList()..sort();
      return out;
    }).distinct((List<String> a, List<String> b) =>
        a.length == b.length &&
        List<int>.generate(a.length, (int i) => i)
            .every((int i) => a[i] == b[i]));
  }

  /// Case-insensitive lookup, creating the activity when it is new.
  Future<ActivityRow> getOrCreate(String rawName, {String? groupName}) async {
    final String name = rawName.trim();
    if (name.isEmpty) {
      throw ArgumentError('An activity needs a name');
    }
    final ActivityRow? existing = await findByName(name);
    if (existing != null) {
      // An explicit group choice at start time updates the activity.
      final String? group = _cleanGroup(groupName);
      if (group != null && group != existing.groupName) {
        await (_db.update(_db.activities)
              ..where(($ActivitiesTable t) => t.id.equals(existing.id)))
            .write(ActivitiesCompanion(groupName: Value<String?>(group)));
        return existing.copyWith(groupName: Value<String?>(group));
      }
      return existing;
    }

    final int count = await _activityCount();
    final int id = await _db.into(_db.activities).insert(ActivitiesCompanion.insert(
          name: name,
          groupName: Value<String?>(_cleanGroup(groupName)),
          colorSeed: Value<int>(count),
          createdAt: DateTime.now(),
        ));
    return (await (_db.select(_db.activities)
              ..where(($ActivitiesTable t) => t.id.equals(id)))
            .getSingle());
  }

  Future<ActivityRow?> findByName(String rawName) {
    final String name = rawName.trim();
    return (_db.select(_db.activities)
          ..where(($ActivitiesTable t) => t.name.lower().equals(name.toLowerCase()))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Returns false when the name already exists (duplicates are rejected
  /// silently, per the spec).
  Future<bool> addActivity(String rawName) async {
    final String name = rawName.trim();
    if (name.isEmpty) return false;
    if (await findByName(name) != null) return false;
    final int count = await _activityCount();
    await _db.into(_db.activities).insert(ActivitiesCompanion.insert(
          name: name,
          colorSeed: Value<int>(count),
          createdAt: DateTime.now(),
        ));
    return true;
  }

  Future<void> assignGroup(List<int> activityIds, String? groupName) async {
    if (activityIds.isEmpty) return;
    await (_db.update(_db.activities)
          ..where(($ActivitiesTable t) => t.id.isIn(activityIds)))
        .write(ActivitiesCompanion(groupName: Value<String?>(_cleanGroup(groupName))));
  }

  /// Drops a whole group: every activity in it falls back to Ungrouped.
  Future<void> ungroup(String groupName) async {
    await (_db.update(_db.activities)
          ..where(($ActivitiesTable t) => t.groupName.equals(groupName)))
        .write(const ActivitiesCompanion(groupName: Value<String?>(null)));
  }

  Future<void> renameActivity(int id, String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await (_db.update(_db.activities)
          ..where(($ActivitiesTable t) => t.id.equals(id)))
        .write(ActivitiesCompanion(name: Value<String>(trimmed)));
  }

  Future<void> deleteActivity(int id) async {
    await (_db.delete(_db.activities)
          ..where(($ActivitiesTable t) => t.id.equals(id)))
        .go();
  }

  Future<void> touchLastUsed(int id) async {
    await (_db.update(_db.activities)
          ..where(($ActivitiesTable t) => t.id.equals(id)))
        .write(ActivitiesCompanion(lastUsedAt: Value<DateTime>(DateTime.now())));
  }

  Future<int> _activityCount() async {
    final Expression<int> count = _db.activities.id.count();
    final TypedResult row =
        await (_db.selectOnly(_db.activities)..addColumns(<Expression<Object>>[count]))
            .getSingle();
    return row.read(count) ?? 0;
  }

  static String? _cleanGroup(String? raw) {
    final String v = (raw ?? '').trim();
    if (v.isEmpty || v.toLowerCase() == kUngrouped.toLowerCase()) return null;
    return v;
  }

  static bool _sameSummaries(List<ActivitySummary> a, List<ActivitySummary> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].name != b[i].name ||
          a[i].groupName != b[i].groupName ||
          a[i].total != b[i].total ||
          a[i].blockCount != b[i].blockCount) {
        return false;
      }
    }
    return true;
  }
}
