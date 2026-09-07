import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../data/db/database.dart';
import '../data/prefs/settings_store.dart';
import '../data/repositories/activity_repository.dart';
import '../data/repositories/tracking_repository.dart';
import '../features/sync/google_calendar_service.dart';
import '../features/sync/sync_engine.dart';

const String kSyncTaskName = 'tally.pushBlocks';
const String kSyncTaskUnique = 'tally.pushBlocks.periodic';
const String kSyncTaskOneOff = 'tally.pushBlocks.oneOff';

/// Runs in its own isolate: opens the database, pushes whatever is dirty, and
/// reports failure so WorkManager can back off.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((String task, Map<String, dynamic>? input) async {
    WidgetsFlutterBinding.ensureInitialized();
    final AppDatabase db = AppDatabase();
    try {
      final SettingsStore store = await SettingsStore.open();
      final Settings settings = store.read();
      if (!settings.isConnected || settings.direction == SyncDirection.pull) {
        return true;
      }
      final GoogleCalendarService calendar = GoogleCalendarService();
      if (!await calendar.restore()) {
        await store.write(settings.copyWith(needsReconnect: true));
        return true; // nothing retryable — the user has to reconnect.
      }
      final ActivityRepository activities = ActivityRepository(db);
      final SyncEngine engine =
          SyncEngine(TrackingRepository(db, activities), calendar);
      final SyncOutcome outcome = await engine.push(settings);
      if (outcome.error == 'reconnect') {
        await store.write(settings.copyWith(needsReconnect: true));
        return true;
      }
      await store.write(settings.copyWith(lastSyncAt: DateTime.now()));
      return outcome.failed == 0;
    } on Exception {
      return false; // let WorkManager retry with backoff.
    } finally {
      await db.close();
    }
  });
}

class BackgroundSync {
  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static Future<void> initialize() async {
    if (!_supported) return;
    await Workmanager().initialize(backgroundSyncDispatcher);
  }

  static Future<void> schedulePeriodic() async {
    if (!_supported) return;
    await Workmanager().registerPeriodicTask(
      kSyncTaskUnique,
      kSyncTaskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 1),
    );
  }

  /// Fired right after Stop, so a finished block does not wait 15 minutes.
  static Future<void> pushNow() async {
    if (!_supported) return;
    await Workmanager().registerOneOffTask(
      kSyncTaskOneOff,
      kSyncTaskName,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 1),
    );
  }

  static Future<void> cancel() async {
    if (!_supported) return;
    await Workmanager().cancelByUniqueName(kSyncTaskUnique);
    await Workmanager().cancelByUniqueName(kSyncTaskOneOff);
  }
}
