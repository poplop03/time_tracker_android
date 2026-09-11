import 'package:drift/drift.dart';

import '../../core/time/day.dart';
import '../../domain/block_edit.dart';
import '../../domain/models.dart';
import '../db/database.dart';
import 'activity_repository.dart';

/// Raised when a retroactive block cannot be placed without destroying an
/// existing one.
class OverlapRejected implements Exception {
  OverlapRejected(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What placing a retroactive block actually did, so the UI can be honest
/// about it.
class BlockPlacement {
  const BlockPlacement({required this.trimmed, required this.removed});
  final int trimmed;
  final int removed;
}

/// Owns every write to `blocks`, including the "at most one running block"
/// invariant. Elapsed time is never accumulated — only `startedAt` is stored.
class TrackingRepository {
  TrackingRepository(this._db, this._activities);

  final AppDatabase _db;
  final ActivityRepository _activities;

  JoinedSelectStatement<HasResultSet, dynamic> _joined() {
    return _db.select(_db.blocks).join(<Join<HasResultSet, dynamic>>[
      innerJoin(_db.activities, _db.activities.id.equalsExp(_db.blocks.activityId)),
    ]);
  }

  TrackedBlock _map(TypedResult row) {
    final BlockRow b = row.readTable(_db.blocks);
    final ActivityRow a = row.readTable(_db.activities);
    return TrackedBlock(
      id: b.id,
      activityId: a.id,
      activityName: a.name,
      groupName: a.groupName,
      colorSeed: a.colorSeed,
      startedAt: b.startedAt.toLocal(),
      endedAt: b.endedAt?.toLocal(),
      note: b.note,
      calendarEventId: b.calendarEventId,
      syncDirty: b.syncDirty,
    );
  }

  /// Blocks that overlap the local day containing [day], oldest first.
  Stream<List<TrackedBlock>> watchDay(DateTime day) {
    final DateTime from = startOfDay(day);
    final DateTime to = endOfDay(day);
    final JoinedSelectStatement<HasResultSet, dynamic> query = _joined()
      ..where(_db.blocks.startedAt.isBiggerOrEqualValue(from) &
          _db.blocks.startedAt.isSmallerThanValue(to))
      ..orderBy(<OrderingTerm>[OrderingTerm(expression: _db.blocks.startedAt)]);
    return query.watch().map(
        (List<TypedResult> rows) => rows.map(_map).toList(growable: false));
  }

  /// Blocks starting within [from, to), oldest first.
  Stream<List<TrackedBlock>> watchRange(DateTime from, DateTime to) {
    final JoinedSelectStatement<HasResultSet, dynamic> query = _joined()
      ..where(_db.blocks.startedAt.isBiggerOrEqualValue(from) &
          _db.blocks.startedAt.isSmallerThanValue(to))
      ..orderBy(<OrderingTerm>[OrderingTerm(expression: _db.blocks.startedAt)]);
    return query.watch().map(
        (List<TypedResult> rows) => rows.map(_map).toList(growable: false));
  }

  Future<List<TrackedBlock>> blocksInRange(DateTime from, DateTime to) async {
    final JoinedSelectStatement<HasResultSet, dynamic> query = _joined()
      ..where(_db.blocks.startedAt.isBiggerOrEqualValue(from) &
          _db.blocks.startedAt.isSmallerThanValue(to))
      ..orderBy(<OrderingTerm>[OrderingTerm(expression: _db.blocks.startedAt)]);
    return (await query.get()).map(_map).toList(growable: false);
  }

  /// One activity's blocks, newest first, capped at [limit] so a long history
  /// is paged in rather than loaded whole.
  Stream<List<TrackedBlock>> watchActivityBlocks(int activityId,
      {int limit = 50}) {
    final JoinedSelectStatement<HasResultSet, dynamic> query = _joined()
      ..where(_db.blocks.activityId.equals(activityId))
      ..orderBy(<OrderingTerm>[
        OrderingTerm(expression: _db.blocks.startedAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return query.watch().map(
        (List<TypedResult> rows) => rows.map(_map).toList(growable: false));
  }

  /// The single running block, if any.
  Stream<TrackedBlock?> watchRunning() {
    final JoinedSelectStatement<HasResultSet, dynamic> query = _joined()
      ..where(_db.blocks.endedAt.isNull())
      ..orderBy(<OrderingTerm>[
        OrderingTerm(expression: _db.blocks.startedAt, mode: OrderingMode.desc),
      ])
      ..limit(1);
    return query.watch().map((List<TypedResult> rows) =>
        rows.isEmpty ? null : _map(rows.first));
  }

  Future<TrackedBlock?> currentRunning() async {
    final JoinedSelectStatement<HasResultSet, dynamic> query = _joined()
      ..where(_db.blocks.endedAt.isNull())
      ..orderBy(<OrderingTerm>[
        OrderingTerm(expression: _db.blocks.startedAt, mode: OrderingMode.desc),
      ])
      ..limit(1);
    final List<TypedResult> rows = await query.get();
    return rows.isEmpty ? null : _map(rows.first);
  }

  /// Starts tracking [activityName]. Any block still running is closed first,
  /// so the "one open block" invariant holds even if the UI misbehaves.
  Future<TrackedBlock> start(String activityName, {String? groupName}) async {
    final DateTime now = DateTime.now();
    return _db.transaction(() async {
      await _closeAllOpen(now);
      final ActivityRow activity =
          await _activities.getOrCreate(activityName, groupName: groupName);
      await _activities.touchLastUsed(activity.id);
      await _db.into(_db.blocks).insert(BlocksCompanion.insert(
            activityId: activity.id,
            startedAt: now,
          ));
      final TrackedBlock? running = await currentRunning();
      return running!;
    });
  }

  /// Ends the running block. Returns it, or null when nothing was running.
  Future<TrackedBlock?> stop({DateTime? at}) async {
    final DateTime now = at ?? DateTime.now();
    final TrackedBlock? running = await currentRunning();
    if (running == null) return null;
    final DateTime end =
        now.isAfter(running.startedAt) ? now : running.startedAt;
    await (_db.update(_db.blocks)
          ..where(($BlocksTable t) => t.id.equals(running.id)))
        .write(BlocksCompanion(
      endedAt: Value<DateTime?>(end),
      syncDirty: const Value<bool>(true),
    ));
    return TrackedBlock(
      id: running.id,
      activityId: running.activityId,
      activityName: running.activityName,
      groupName: running.groupName,
      colorSeed: running.colorSeed,
      startedAt: running.startedAt,
      endedAt: end,
    );
  }

  /// Drops the running block entirely (used by "End at last activity" when a
  /// stale timer has been running for more than half a day).
  Future<void> discardRunning() async {
    final TrackedBlock? running = await currentRunning();
    if (running == null) return;
    await (_db.delete(_db.blocks)
          ..where(($BlocksTable t) => t.id.equals(running.id)))
        .go();
  }

  Future<void> _closeAllOpen(DateTime now) async {
    await (_db.update(_db.blocks)..where(($BlocksTable t) => t.endedAt.isNull()))
        .write(BlocksCompanion(
      endedAt: Value<DateTime?>(now),
      syncDirty: const Value<bool>(true),
    ));
  }

  /// Places a block the user missed. Existing blocks that partially overlap are
  /// trimmed; a block fully covered by the new one is removed; a new block
  /// fully inside an existing one is rejected.
  Future<BlockPlacement> addRetroactive({
    required String activityName,
    String? groupName,
    required DateTime start,
    required DateTime end,
    String? note,
  }) async {
    if (!end.isAfter(start)) {
      throw OverlapRejected('That block would have no length.');
    }

    return _db.transaction(() async {
      final BlockPlacement placement = await _makeRoom(start, end);
      final ActivityRow activity =
          await _activities.getOrCreate(activityName, groupName: groupName);
      await _db.into(_db.blocks).insert(BlocksCompanion.insert(
            activityId: activity.id,
            startedAt: start,
            endedAt: Value<DateTime?>(end),
            note: Value<String?>(cleanNote(note)),
          ));
      return placement;
    });
  }

  /// Changes a block's times and description, under the same overlap rules as
  /// filling in a missed block. A running block keeps its times — only its
  /// description can change until the timer is stopped, because the timer and
  /// its notification both hang off the stored start.
  Future<BlockPlacement> editBlock({
    required int id,
    required DateTime start,
    DateTime? end,
    String? note,
  }) async {
    return _db.transaction(() async {
      final BlockRow? row = await (_db.select(_db.blocks)
            ..where(($BlocksTable t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) throw OverlapRejected('That block no longer exists.');

      if (row.endedAt == null) {
        await (_db.update(_db.blocks)
              ..where(($BlocksTable t) => t.id.equals(id)))
            .write(BlocksCompanion(note: Value<String?>(cleanNote(note))));
        return const BlockPlacement(trimmed: 0, removed: 0);
      }

      final String? problem = end == null
          ? 'A finished block needs an end time.'
          : blockTimesProblem(start: start, end: end, now: DateTime.now());
      if (problem != null) throw OverlapRejected(problem);

      final BlockPlacement placement =
          await _makeRoom(start, end!, excludeId: id);
      await (_db.update(_db.blocks)..where(($BlocksTable t) => t.id.equals(id)))
          .write(BlocksCompanion(
        startedAt: Value<DateTime>(start),
        endedAt: Value<DateTime?>(end),
        note: Value<String?>(cleanNote(note)),
        syncDirty: const Value<bool>(true),
      ));
      return placement;
    });
  }

  /// Clears [start, end) for a block. Blocks that partially overlap are
  /// trimmed and blocks it fully covers are removed; a block that would swallow
  /// it, or the running timer, rejects the change before anything is written.
  /// [excludeId] is the block being edited, which must not collide with itself.
  Future<BlockPlacement> _makeRoom(
    DateTime start,
    DateTime end, {
    int? excludeId,
  }) async {
    final List<TrackedBlock> overlapping = (await _overlapping(start, end))
        .where((TrackedBlock b) => b.id != excludeId)
        .toList();

    for (final TrackedBlock other in overlapping) {
      if (other.isRunning) {
        throw OverlapRejected(
            'That overlaps the timer running right now. Stop it first.');
      }
      final bool contains =
          !other.startedAt.isAfter(start) && !other.endedAt!.isBefore(end);
      if (contains) {
        throw OverlapRejected(
            '“${other.activityName}” already covers that time.');
      }
    }

    int trimmed = 0;
    int removed = 0;
    for (final TrackedBlock other in overlapping) {
      final DateTime otherStart = other.startedAt;
      final DateTime otherEnd = other.endedAt!;
      final bool covered = !start.isAfter(otherStart) && !end.isBefore(otherEnd);
      if (covered) {
        await (_db.delete(_db.blocks)
              ..where(($BlocksTable t) => t.id.equals(other.id)))
            .go();
        removed++;
        continue;
      }
      if (otherStart.isBefore(start)) {
        await (_db.update(_db.blocks)
              ..where(($BlocksTable t) => t.id.equals(other.id)))
            .write(BlocksCompanion(
          endedAt: Value<DateTime?>(start),
          syncDirty: const Value<bool>(true),
        ));
      } else {
        await (_db.update(_db.blocks)
              ..where(($BlocksTable t) => t.id.equals(other.id)))
            .write(BlocksCompanion(
          startedAt: Value<DateTime>(end),
          syncDirty: const Value<bool>(true),
        ));
      }
      trimmed++;
    }
    return BlockPlacement(trimmed: trimmed, removed: removed);
  }

  Future<List<TrackedBlock>> _overlapping(DateTime start, DateTime end) async {
    final JoinedSelectStatement<HasResultSet, dynamic> query = _joined()
      ..where(_db.blocks.startedAt.isSmallerThanValue(end) &
          (_db.blocks.endedAt.isNull() |
              _db.blocks.endedAt.isBiggerThanValue(start)));
    return (await query.get()).map(_map).toList();
  }

  Future<void> updateBlock(int id,
      {DateTime? start, DateTime? end, String? note}) async {
    await (_db.update(_db.blocks)..where(($BlocksTable t) => t.id.equals(id)))
        .write(BlocksCompanion(
      startedAt: start == null ? const Value<DateTime>.absent() : Value<DateTime>(start),
      endedAt: end == null ? const Value<DateTime?>.absent() : Value<DateTime?>(end),
      note: note == null ? const Value<String?>.absent() : Value<String?>(note),
      syncDirty: const Value<bool>(true),
    ));
  }

  Future<void> deleteBlock(int id) async {
    await (_db.delete(_db.blocks)..where(($BlocksTable t) => t.id.equals(id)))
        .go();
  }

  // ---- sync support -------------------------------------------------------

  /// Finished blocks that still need pushing, oldest first.
  Future<List<TrackedBlock>> dirtyBlocks({int limit = 200}) async {
    final JoinedSelectStatement<HasResultSet, dynamic> query = _joined()
      ..where(_db.blocks.syncDirty.equals(true) & _db.blocks.endedAt.isNotNull())
      ..orderBy(<OrderingTerm>[OrderingTerm(expression: _db.blocks.startedAt)])
      ..limit(limit);
    return (await query.get()).map(_map).toList(growable: false);
  }

  Stream<int> watchPendingCount() {
    final Expression<int> count = _db.blocks.id.count();
    final JoinedSelectStatement<HasResultSet, dynamic> query =
        _db.selectOnly(_db.blocks)
          ..addColumns(<Expression<Object>>[count])
          ..where(_db.blocks.syncDirty.equals(true) &
              _db.blocks.endedAt.isNotNull());
    return query.watchSingle().map((TypedResult row) => row.read(count) ?? 0);
  }

  Future<void> markSynced(int blockId, String eventId) async {
    await (_db.update(_db.blocks)
          ..where(($BlocksTable t) => t.id.equals(blockId)))
        .write(BlocksCompanion(
      calendarEventId: Value<String?>(eventId),
      syncDirty: const Value<bool>(false),
    ));
  }

  Future<void> markAllDirty() async {
    await _db.update(_db.blocks).write(const BlocksCompanion(
          syncDirty: Value<bool>(true),
        ));
  }

  /// Used when a pulled suggestion is accepted.
  Future<void> acceptSuggestion({
    required String title,
    required DateTime start,
    required DateTime end,
    required String eventId,
  }) async {
    final ActivityRow activity = await _activities.getOrCreate(title);
    await _db.into(_db.blocks).insert(BlocksCompanion.insert(
          activityId: activity.id,
          startedAt: start,
          endedAt: Value<DateTime?>(end),
          calendarEventId: Value<String?>(eventId),
          syncDirty: const Value<bool>(false),
        ));
  }

  Future<bool> hasEventId(String eventId) async {
    final BlockRow? row = await (_db.select(_db.blocks)
          ..where(($BlocksTable t) => t.calendarEventId.equals(eventId))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  /// All blocks, oldest first — used only by CSV export.
  Future<List<TrackedBlock>> allBlocks() async {
    final JoinedSelectStatement<HasResultSet, dynamic> query = _joined()
      ..orderBy(<OrderingTerm>[OrderingTerm(expression: _db.blocks.startedAt)]);
    return (await query.get()).map(_map).toList(growable: false);
  }
}
