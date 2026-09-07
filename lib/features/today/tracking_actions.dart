import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/prefs/settings_store.dart';
import '../../data/repositories/tracking_repository.dart';
import '../../domain/models.dart';
import '../../providers.dart';
import '../../services/background_sync.dart';
import '../../services/timer_service.dart';

/// A running block older than this is almost certainly a timer the user forgot
/// to stop, so Today asks about it instead of quietly counting.
const Duration kStaleAfter = Duration(hours: 12);

/// Start/stop and the cold-start reconciliation, in one place so the database,
/// the notification and the sync queue never drift apart.
class TrackingActions {
  TrackingActions(this._ref);

  final Ref _ref;

  TrackingRepository get _blocks => _ref.read(trackingRepositoryProvider);
  TimerService get _timer => _ref.read(timerServiceProvider);

  Future<void> start(String activityName, {String? groupName}) async {
    final TrackedBlock block =
        await _blocks.start(activityName, groupName: groupName);
    await _timer.start(
      activityName: block.activityName,
      startedAt: block.startedAt,
    );
  }

  Future<void> stop({DateTime? at}) async {
    final TrackedBlock? finished = await _blocks.stop(at: at);
    await _timer.stop();
    if (finished == null) return;
    final Settings settings = _ref.read(settingsProvider);
    if (settings.isConnected && settings.direction != SyncDirection.pull) {
      await BackgroundSync.pushNow();
    }
  }

  /// Ends a forgotten timer at the last moment we know the user was active:
  /// the end of the previous block, or the start of this one.
  Future<void> endAtLastActivity() async {
    final TrackedBlock? running = await _blocks.currentRunning();
    if (running == null) return;
    final List<TrackedBlock> before = await _blocks.blocksInRange(
      running.startedAt.subtract(const Duration(days: 2)),
      running.startedAt,
    );
    DateTime end = running.startedAt;
    for (final TrackedBlock b in before) {
      final DateTime? e = b.endedAt;
      if (e != null && e.isAfter(end) && e.isBefore(DateTime.now())) end = e;
    }
    await stop(at: end);
  }

  /// Called once on app start: apply a Stop pressed from the notification while
  /// the UI was dead, otherwise put the notification back for a block that is
  /// still running.
  Future<void> reconcile() async {
    final DateTime? pendingStop = await _timer.takePendingStop();
    if (pendingStop != null) {
      await stop(at: pendingStop);
      return;
    }
    final TrackedBlock? running = await _blocks.currentRunning();
    if (running == null) {
      await _timer.stop();
      return;
    }
    await _timer.start(
      activityName: running.activityName,
      startedAt: running.startedAt,
    );
  }
}

final Provider<TrackingActions> trackingActionsProvider =
    Provider<TrackingActions>((Ref ref) => TrackingActions(ref));
