import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SyncDirection { push, pull, both }

/// Everything the app remembers outside the database.
@immutable
class Settings {
  const Settings({
    this.use24h = false,
    this.calendarId,
    this.calendarName,
    this.accountEmail,
    this.direction = SyncDirection.push,
    this.onlyLongBlocks = true,
    this.includeActivityName = true,
    this.lastSyncAt,
    this.needsReconnect = false,
    this.runningStartedAtMs,
    this.runningActivity,
  });

  final bool use24h;
  final String? calendarId;
  final String? calendarName;

  /// The Google account the user signed in with. Kept so the Sync tab can say
  /// who is connected after a restart, not just in the session that signed in.
  final String? accountEmail;
  final SyncDirection direction;
  final bool onlyLongBlocks;
  final bool includeActivityName;
  final DateTime? lastSyncAt;
  final bool needsReconnect;

  /// Mirror of the running block's start, so the foreground service and a cold
  /// start can both recover the timer without touching the database.
  final int? runningStartedAtMs;
  final String? runningActivity;

  bool get isConnected => calendarId != null;

  Settings copyWith({
    bool? use24h,
    String? calendarId,
    String? calendarName,
    String? accountEmail,
    SyncDirection? direction,
    bool? onlyLongBlocks,
    bool? includeActivityName,
    DateTime? lastSyncAt,
    bool? needsReconnect,
    int? runningStartedAtMs,
    String? runningActivity,
    bool clearCalendar = false,
    bool clearRunning = false,
  }) {
    return Settings(
      use24h: use24h ?? this.use24h,
      calendarId: clearCalendar ? null : (calendarId ?? this.calendarId),
      calendarName: clearCalendar ? null : (calendarName ?? this.calendarName),
      accountEmail: clearCalendar ? null : (accountEmail ?? this.accountEmail),
      direction: direction ?? this.direction,
      onlyLongBlocks: onlyLongBlocks ?? this.onlyLongBlocks,
      includeActivityName: includeActivityName ?? this.includeActivityName,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      needsReconnect: needsReconnect ?? this.needsReconnect,
      runningStartedAtMs:
          clearRunning ? null : (runningStartedAtMs ?? this.runningStartedAtMs),
      runningActivity:
          clearRunning ? null : (runningActivity ?? this.runningActivity),
    );
  }
}

class SettingsStore {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _kUse24h = 'use24h';
  static const String _kCalendarId = 'calendarId';
  static const String _kCalendarName = 'calendarName';
  static const String _kAccountEmail = 'accountEmail';
  static const String _kDirection = 'syncDirection';
  static const String _kOnlyLong = 'onlyLongBlocks';
  static const String _kIncludeName = 'includeActivityName';
  static const String _kLastSync = 'lastSyncAt';
  static const String _kNeedsReconnect = 'needsReconnect';
  static const String _kRunningStart = 'runningStartedAtMs';
  static const String _kRunningActivity = 'runningActivity';

  static Future<SettingsStore> open() async =>
      SettingsStore(await SharedPreferences.getInstance());

  Settings read() {
    final int? lastSync = _prefs.getInt(_kLastSync);
    return Settings(
      use24h: _prefs.getBool(_kUse24h) ?? false,
      calendarId: _prefs.getString(_kCalendarId),
      calendarName: _prefs.getString(_kCalendarName),
      accountEmail: _prefs.getString(_kAccountEmail),
      direction: SyncDirection.values[
          (_prefs.getInt(_kDirection) ?? 0).clamp(0, SyncDirection.values.length - 1)],
      onlyLongBlocks: _prefs.getBool(_kOnlyLong) ?? true,
      includeActivityName: _prefs.getBool(_kIncludeName) ?? true,
      lastSyncAt:
          lastSync == null ? null : DateTime.fromMillisecondsSinceEpoch(lastSync),
      needsReconnect: _prefs.getBool(_kNeedsReconnect) ?? false,
      runningStartedAtMs: _prefs.getInt(_kRunningStart),
      runningActivity: _prefs.getString(_kRunningActivity),
    );
  }

  Future<void> write(Settings s) async {
    await _prefs.setBool(_kUse24h, s.use24h);
    await _prefs.setInt(_kDirection, s.direction.index);
    await _prefs.setBool(_kOnlyLong, s.onlyLongBlocks);
    await _prefs.setBool(_kIncludeName, s.includeActivityName);
    await _prefs.setBool(_kNeedsReconnect, s.needsReconnect);
    if (s.accountEmail == null) {
      await _prefs.remove(_kAccountEmail);
    } else {
      await _prefs.setString(_kAccountEmail, s.accountEmail!);
    }
    if (s.calendarId == null) {
      await _prefs.remove(_kCalendarId);
      await _prefs.remove(_kCalendarName);
    } else {
      await _prefs.setString(_kCalendarId, s.calendarId!);
      await _prefs.setString(_kCalendarName, s.calendarName ?? 'Calendar');
    }
    if (s.lastSyncAt == null) {
      await _prefs.remove(_kLastSync);
    } else {
      await _prefs.setInt(_kLastSync, s.lastSyncAt!.millisecondsSinceEpoch);
    }
    if (s.runningStartedAtMs == null) {
      await _prefs.remove(_kRunningStart);
      await _prefs.remove(_kRunningActivity);
    } else {
      await _prefs.setInt(_kRunningStart, s.runningStartedAtMs!);
      await _prefs.setString(_kRunningActivity, s.runningActivity ?? '');
    }
  }
}
