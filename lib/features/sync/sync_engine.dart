import '../../data/prefs/settings_store.dart';
import '../../data/repositories/tracking_repository.dart';
import '../../domain/models.dart';
import 'device_calendar_service.dart';

/// Blocks shorter than this are skipped when "only sync blocks over 15
/// minutes" is on.
const Duration kMinSyncedBlock = Duration(minutes: 15);

/// Pushes dirty blocks to the chosen calendar. Shared by the Sync tab's
/// "Sync now" and the WorkManager periodic task.
class SyncEngine {
  SyncEngine(this._blocks, this._calendar);

  final TrackingRepository _blocks;
  final DeviceCalendarService _calendar;

  Future<SyncOutcome> push(Settings settings) async {
    final String? calendarId = settings.calendarId;
    if (calendarId == null) {
      return const SyncOutcome(pushed: 0, skipped: 0, error: 'No calendar picked yet.');
    }
    if (settings.direction == SyncDirection.pull) {
      return const SyncOutcome(pushed: 0, skipped: 0);
    }

    final List<TrackedBlock> dirty = await _blocks.dirtyBlocks();
    int pushed = 0;
    int skipped = 0;
    int failed = 0;
    String? error;

    for (final TrackedBlock block in dirty) {
      if (settings.onlyLongBlocks && block.duration < kMinSyncedBlock) {
        skipped++;
        continue;
      }
      try {
        final String eventId = await _calendar.pushBlock(
          calendarId: calendarId,
          block: block,
          includeActivityName: settings.includeActivityName,
        );
        await _blocks.markSynced(block.id, eventId);
        pushed++;
      } on CalendarPermissionDenied {
        // Nothing else will succeed until the permission is granted, so stop.
        return SyncOutcome(
          pushed: pushed,
          skipped: skipped,
          failed: dirty.length - pushed - skipped,
          error: 'permission',
        );
      } on Exception catch (e) {
        failed++;
        error = e.toString();
      }
    }

    return SyncOutcome(
        pushed: pushed, skipped: skipped, failed: failed, error: error);
  }

  Future<List<PulledSuggestion>> pull(Settings settings, DateTime now) async {
    final String? calendarId = settings.calendarId;
    if (calendarId == null || settings.direction == SyncDirection.push) {
      return const <PulledSuggestion>[];
    }
    final DateTime monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final List<PulledSuggestion> raw = await _calendar.pullSuggestions(
      calendarId: calendarId,
      from: monday,
      to: monday.add(const Duration(days: 7)),
    );

    final List<PulledSuggestion> out = <PulledSuggestion>[];
    for (final PulledSuggestion s in raw) {
      if (await _blocks.hasEventId(s.eventId)) continue;
      out.add(s);
    }
    return out;
  }
}
