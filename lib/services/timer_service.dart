import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../core/time/formatting.dart';

/// Keys shared between the UI isolate and the foreground task isolate.
class TimerKeys {
  const TimerKeys._();
  static const String startedAtMs = 'tally.startedAtMs';
  static const String activityName = 'tally.activityName';
  static const String stopRequestedAtMs = 'tally.stopRequestedAtMs';
}

const int _kServiceId = 2601;
const String _kStopButtonId = 'tally_stop';

/// Entry point for the foreground service isolate.
@pragma('vm:entry-point')
void startTimerCallback() {
  FlutterForegroundTask.setTaskHandler(_TimerTaskHandler());
}

/// Keeps the ongoing notification in step with the running block. It derives
/// elapsed time from the persisted start, never from an accumulator.
class _TimerTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _refresh();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _refresh();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id != _kStopButtonId) return;
    // The UI isolate owns the database. Record the moment and let whichever
    // side is alive apply it.
    FlutterForegroundTask.saveData(
      key: TimerKeys.stopRequestedAtMs,
      value: DateTime.now().millisecondsSinceEpoch,
    );
    FlutterForegroundTask.sendDataToMain(<String, dynamic>{
      'stopAtMs': DateTime.now().millisecondsSinceEpoch,
    });
    FlutterForegroundTask.stopService();
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  Future<void> _refresh() async {
    final int? startedAt =
        await FlutterForegroundTask.getData<int>(key: TimerKeys.startedAtMs);
    if (startedAt == null) return;
    final String name =
        await FlutterForegroundTask.getData<String>(key: TimerKeys.activityName) ??
            'Tracking';
    final Duration elapsed = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(startedAt));
    await FlutterForegroundTask.updateService(
      notificationTitle: name,
      notificationText: formatStopwatch(elapsed),
    );
  }
}

/// Thin wrapper the UI talks to. All calls are no-ops off Android.
class TimerService {
  bool _initialised = false;

  bool get _supported => !kIsWeb && Platform.isAndroid;

  void init() {
    if (_initialised || !_supported) return;
    _initialised = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'tally_timer',
        channelName: 'Running timer',
        channelDescription: 'Shows the activity Tally is currently tracking.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  Future<void> requestPermissions() async {
    if (!_supported) return;
    final NotificationPermission permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
  }

  Future<void> start({
    required String activityName,
    required DateTime startedAt,
  }) async {
    if (!_supported) return;
    init();
    await FlutterForegroundTask.saveData(
      key: TimerKeys.startedAtMs,
      value: startedAt.millisecondsSinceEpoch,
    );
    await FlutterForegroundTask.saveData(
      key: TimerKeys.activityName,
      value: activityName,
    );
    await FlutterForegroundTask.removeData(key: TimerKeys.stopRequestedAtMs);

    final List<NotificationButton> buttons = <NotificationButton>[
      const NotificationButton(id: _kStopButtonId, text: 'Stop'),
    ];

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: activityName,
        notificationText: formatStopwatch(DateTime.now().difference(startedAt)),
      );
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: _kServiceId,
      serviceTypes: <ForegroundServiceTypes>[ForegroundServiceTypes.dataSync],
      notificationTitle: activityName,
      notificationText: formatStopwatch(DateTime.now().difference(startedAt)),
      notificationButtons: buttons,
      notificationInitialRoute: '/',
      callback: startTimerCallback,
    );
  }

  Future<void> stop() async {
    if (!_supported) return;
    await FlutterForegroundTask.removeData(key: TimerKeys.startedAtMs);
    await FlutterForegroundTask.removeData(key: TimerKeys.activityName);
    await FlutterForegroundTask.removeData(key: TimerKeys.stopRequestedAtMs);
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  /// A Stop pressed on the notification while the UI was dead.
  Future<DateTime?> takePendingStop() async {
    if (!_supported) return null;
    final int? at = await FlutterForegroundTask.getData<int>(
        key: TimerKeys.stopRequestedAtMs);
    if (at == null) return null;
    await FlutterForegroundTask.removeData(key: TimerKeys.stopRequestedAtMs);
    return DateTime.fromMillisecondsSinceEpoch(at);
  }
}
