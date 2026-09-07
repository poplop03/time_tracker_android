import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/time/day.dart';
import 'data/db/database.dart';
import 'data/prefs/settings_store.dart';
import 'data/repositories/activity_repository.dart';
import 'data/repositories/tracking_repository.dart';
import 'domain/breakdown.dart';
import 'domain/insights.dart';
import 'domain/models.dart';
import 'features/sync/google_calendar_service.dart';
import 'features/sync/sync_engine.dart';
import 'services/timer_service.dart';

/// Overridden in main() once the database and prefs are open.
final Provider<AppDatabase> databaseProvider = Provider<AppDatabase>(
  (Ref ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final Provider<SettingsStore> settingsStoreProvider = Provider<SettingsStore>(
  (Ref ref) => throw UnimplementedError('settingsStoreProvider must be overridden'),
);

final Provider<ActivityRepository> activityRepositoryProvider =
    Provider<ActivityRepository>(
        (Ref ref) => ActivityRepository(ref.watch(databaseProvider)));

final Provider<TrackingRepository> trackingRepositoryProvider =
    Provider<TrackingRepository>((Ref ref) => TrackingRepository(
          ref.watch(databaseProvider),
          ref.watch(activityRepositoryProvider),
        ));

final Provider<TimerService> timerServiceProvider =
    Provider<TimerService>((Ref ref) => TimerService());

final Provider<GoogleCalendarService> calendarServiceProvider =
    Provider<GoogleCalendarService>((Ref ref) => GoogleCalendarService());

final Provider<SyncEngine> syncEngineProvider = Provider<SyncEngine>(
  (Ref ref) => SyncEngine(
    ref.watch(trackingRepositoryProvider),
    ref.watch(calendarServiceProvider),
  ),
);

// ---- settings ---------------------------------------------------------------

class SettingsController extends Notifier<Settings> {
  @override
  Settings build() => ref.watch(settingsStoreProvider).read();

  Future<void> _save(Settings next) async {
    state = next;
    await ref.read(settingsStoreProvider).write(next);
  }

  Future<void> setUse24h(bool value) => _save(state.copyWith(use24h: value));

  Future<void> setCalendar(String id, String name) =>
      _save(state.copyWith(calendarId: id, calendarName: name, needsReconnect: false));

  /// Remembers which Google account is signed in, so the Sync tab can name it
  /// after a restart rather than only in the session that connected.
  Future<void> setAccount(String? email) =>
      _save(Settings(
        use24h: state.use24h,
        calendarId: state.calendarId,
        calendarName: state.calendarName,
        accountEmail: email,
        direction: state.direction,
        onlyLongBlocks: state.onlyLongBlocks,
        includeActivityName: state.includeActivityName,
        lastSyncAt: state.lastSyncAt,
        needsReconnect: state.needsReconnect,
        runningStartedAtMs: state.runningStartedAtMs,
        runningActivity: state.runningActivity,
      ));

  Future<void> setDirection(SyncDirection d) =>
      _save(state.copyWith(direction: d));

  Future<void> setOnlyLongBlocks(bool v) =>
      _save(state.copyWith(onlyLongBlocks: v));

  Future<void> setIncludeActivityName(bool v) =>
      _save(state.copyWith(includeActivityName: v));

  Future<void> markSynced() => _save(state.copyWith(
        lastSyncAt: DateTime.now(),
        needsReconnect: false,
      ));

  Future<void> markNeedsReconnect() =>
      _save(state.copyWith(needsReconnect: true));

  Future<void> disconnect() => _save(state.copyWith(clearCalendar: true));

  Future<void> reload() async {
    state = ref.read(settingsStoreProvider).read();
  }
}

final NotifierProvider<SettingsController, Settings> settingsProvider =
    NotifierProvider<SettingsController, Settings>(SettingsController.new);

// ---- data streams -----------------------------------------------------------

/// The block currently running, if any. Drives the Today card and the
/// foreground notification.
final StreamProvider<TrackedBlock?> runningBlockProvider =
    StreamProvider<TrackedBlock?>(
        (Ref ref) => ref.watch(trackingRepositoryProvider).watchRunning());

final StreamProvider<List<TrackedBlock>> todayBlocksProvider =
    StreamProvider<List<TrackedBlock>>((Ref ref) => ref
        .watch(trackingRepositoryProvider)
        .watchDay(ref.watch(currentDayProvider)));

final StreamProvider<List<ActivitySummary>> activitiesProvider =
    StreamProvider<List<ActivitySummary>>(
        (Ref ref) => ref.watch(activityRepositoryProvider).watchSummaries());

final StreamProvider<List<String>> groupsProvider = StreamProvider<List<String>>(
    (Ref ref) => ref.watch(activityRepositoryProvider).watchGroups());

final StreamProvider<int> pendingSyncCountProvider = StreamProvider<int>(
    (Ref ref) => ref.watch(trackingRepositoryProvider).watchPendingCount());

/// Which bottom-nav tab is on screen. Only Today needs a live clock, so the
/// ticker below watches this rather than running all day.
class SelectedTab extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

final NotifierProvider<SelectedTab, int> selectedTabProvider =
    NotifierProvider<SelectedTab, int>(SelectedTab.new);

/// A one-second heartbeat, alive only while the Today tab is visible. The tick
/// never mutates a stored duration — it just re-renders derived readouts.
final StreamProvider<DateTime> tickerProvider = StreamProvider<DateTime>(
  (Ref ref) async* {
    yield DateTime.now();
    if (ref.watch(selectedTabProvider) != 0) return;
    yield* Stream<DateTime>.periodic(
        const Duration(seconds: 1), (_) => DateTime.now());
  },
);

/// The local day Today is showing. Derived from the ticker so the screen rolls
/// over at midnight instead of pinning the day the app was opened.
final Provider<DateTime> currentDayProvider = Provider<DateTime>((Ref ref) {
  return startOfDay(ref.watch(tickerProvider).value ?? DateTime.now());
});

/// The last 7 local days of blocks, for the Stats bars and donut.
final StreamProvider<List<TrackedBlock>> weekBlocksProvider =
    StreamProvider<List<TrackedBlock>>((Ref ref) {
  final DateTime now = DateTime.now();
  final DateTime from = startOfDay(now).subtract(const Duration(days: 6));
  return ref
      .watch(trackingRepositoryProvider)
      .watchRange(from, endOfDay(now));
});

/// A 30-day window, for Insights.
final StreamProvider<List<TrackedBlock>> insightWindowProvider =
    StreamProvider<List<TrackedBlock>>((Ref ref) {
  final DateTime now = DateTime.now();
  final DateTime from = startOfDay(now).subtract(const Duration(days: 29));
  return ref
      .watch(trackingRepositoryProvider)
      .watchRange(from, endOfDay(now));
});

// ---- derived ----------------------------------------------------------------

final Provider<List<DayTotal>> weekTotalsProvider =
    Provider<List<DayTotal>>((Ref ref) {
  final List<TrackedBlock> blocks =
      ref.watch(weekBlocksProvider).value ?? const <TrackedBlock>[];
  final DateTime now = DateTime.now();
  final Map<DateTime, Duration> totals = <DateTime, Duration>{};
  for (final TrackedBlock b in blocks) {
    final DateTime day = startOfDay(b.startedAt);
    totals[day] = (totals[day] ?? Duration.zero) + b.durationAt(now);
  }
  return <DayTotal>[
    for (final DateTime day in lastDays(now, 7))
      DayTotal(day: day, total: totals[day] ?? Duration.zero),
  ];
});

final Provider<List<GroupSlice>> weekBreakdownProvider =
    Provider<List<GroupSlice>>((Ref ref) {
  final List<TrackedBlock> blocks =
      ref.watch(weekBlocksProvider).value ?? const <TrackedBlock>[];
  final List<ActivitySummary> activities =
      ref.watch(activitiesProvider).value ?? const <ActivitySummary>[];
  return groupBreakdown(activities, blocks, now: DateTime.now());
});

final Provider<InsightSet> insightsProvider = Provider<InsightSet>((Ref ref) {
  final List<TrackedBlock> blocks =
      ref.watch(insightWindowProvider).value ?? const <TrackedBlock>[];
  return buildInsights(blocks, DateTime.now());
});
