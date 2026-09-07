import 'dart:collection';

import 'package:device_calendar/device_calendar.dart' as dc;
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/models.dart';

/// The user declined the calendar permission, so there is nothing to sync to.
class CalendarPermissionDenied implements Exception {
  @override
  String toString() =>
      'Tally needs permission to read and write your calendar. '
      'You can grant it in Settings › Apps › Tally › Permissions.';
}

/// Something went wrong inside the Android calendar provider.
class CalendarFailure implements Exception {
  CalendarFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A calendar the user can pick in step 2 of setup.
@immutable
class CalendarChoice {
  const CalendarChoice({
    required this.id,
    required this.name,
    this.accountName,
    this.isLocal = false,
  });

  final String id;
  final String name;

  /// The account the calendar belongs to — a Google address for calendars that
  /// sync, or a local account for ones that stay on the device.
  final String? accountName;

  /// A device-only calendar: events in it never reach Google.
  final bool isLocal;
}

/// What one push run did.
@immutable
class SyncOutcome {
  const SyncOutcome({
    required this.pushed,
    required this.skipped,
    this.failed = 0,
    this.error,
  });

  final int pushed;
  final int skipped;
  final int failed;
  final String? error;

  bool get isClean => error == null && failed == 0;
}

/// Writes blocks to the calendar that is already on the phone.
///
/// The user's Google account is signed in at the Android level, so events
/// written here land in their Google Calendar and Android syncs them up. That
/// means no OAuth client, no browser sign-in and no per-install setup — just
/// the calendar permission.
class DeviceCalendarService {
  DeviceCalendarService([dc.DeviceCalendarPlugin? plugin])
      : _plugin = plugin ?? dc.DeviceCalendarPlugin();

  final dc.DeviceCalendarPlugin _plugin;
  bool _timezonesReady = false;
  tz.Location? _local;

  /// Calendars in these accounts are device-only.
  static const Set<String> _localAccountTypes = <String>{'LOCAL', 'local'};

  Future<void> _ensureTimezones() async {
    if (_timezonesReady) return;
    tzdata.initializeTimeZones();
    try {
      final TimezoneInfo zone = await FlutterTimezone.getLocalTimezone();
      _local = tz.getLocation(zone.identifier);
    } on Exception {
      _local = tz.UTC; // still the right instant, just labelled UTC
    }
    _timezonesReady = true;
  }

  Future<bool> hasPermission() async {
    final dc.Result<bool> result = await _plugin.hasPermissions();
    return result.data ?? false;
  }

  /// Asks for the calendar permission. Returns false when the user says no.
  Future<bool> requestPermission() async {
    if (await hasPermission()) return true;
    final dc.Result<bool> result = await _plugin.requestPermissions();
    return result.data ?? false;
  }

  Future<void> _requirePermission() async {
    if (!await requestPermission()) throw CalendarPermissionDenied();
  }

  /// Writable calendars on the device, Google accounts first.
  Future<List<CalendarChoice>> listCalendars() async {
    await _requirePermission();
    final dc.Result<UnmodifiableListView<dc.Calendar>> result =
        await _plugin.retrieveCalendars();
    if (result.data == null) {
      throw CalendarFailure(_describe(result, 'Could not read your calendars.'));
    }

    final List<CalendarChoice> out = <CalendarChoice>[];
    for (final dc.Calendar c in result.data!) {
      if (c.id == null) continue;
      if (c.isReadOnly ?? false) continue; // nothing to push into
      out.add(CalendarChoice(
        id: c.id!,
        name: c.name ?? c.accountName ?? 'Calendar',
        accountName: c.accountName,
        isLocal: _localAccountTypes.contains(c.accountType ?? ''),
      ));
    }

    // Google calendars are the ones that reach the user's other devices, so
    // offer them first.
    out.sort((CalendarChoice a, CalendarChoice b) {
      if (a.isLocal != b.isLocal) return a.isLocal ? 1 : -1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  /// Creates a device-only calendar. Android does not let an app add a calendar
  /// to a Google account, so this one never leaves the phone — the UI says so.
  Future<CalendarChoice> createLocalCalendar(String name) async {
    await _requirePermission();
    final dc.Result<String> result = await _plugin.createCalendar(
      name,
      calendarColor: const Color(0xFFC67139),
      localAccountName: 'Tally',
    );
    final String? id = result.data;
    if (id == null) {
      throw CalendarFailure(
          _describe(result, 'Could not create that calendar.'));
    }
    return CalendarChoice(
        id: id, name: name, accountName: 'Tally', isLocal: true);
  }

  /// Writes one block as an event and returns its id. Updates in place when the
  /// block already has one.
  Future<String> pushBlock({
    required String calendarId,
    required TrackedBlock block,
    required bool includeActivityName,
  }) async {
    await _requirePermission();
    await _ensureTimezones();
    final DateTime? end = block.endedAt;
    if (end == null) {
      throw CalendarFailure('A running block has no end time yet.');
    }

    final tz.Location location = _local ?? tz.UTC;
    final dc.Event event = dc.Event(
      calendarId,
      eventId: block.calendarEventId,
      title: includeActivityName ? block.activityName : block.group,
      description: 'Tracked in Tally',
      start: tz.TZDateTime.from(block.startedAt, location),
      end: tz.TZDateTime.from(end, location),
    );

    final dc.Result<String>? result = await _plugin.createOrUpdateEvent(event);
    final String? id = result?.data;
    if (id == null) {
      throw CalendarFailure(result == null
          ? 'The calendar rejected that event.'
          : _describe(result, 'The calendar rejected that event.'));
    }
    return id;
  }

  Future<void> deleteEvent(String calendarId, String eventId) async {
    await _requirePermission();
    await _plugin.deleteEvent(calendarId, eventId);
  }

  /// Events in [from, to) that could become blocks. All-day events and Tally's
  /// own events are skipped; nothing is written to the database here.
  Future<List<PulledSuggestion>> pullSuggestions({
    required String calendarId,
    required DateTime from,
    required DateTime to,
  }) async {
    await _requirePermission();
    final dc.Result<UnmodifiableListView<dc.Event>> result =
        await _plugin.retrieveEvents(
      calendarId,
      dc.RetrieveEventsParams(startDate: from, endDate: to),
    );
    if (result.data == null) return const <PulledSuggestion>[];

    final List<PulledSuggestion> out = <PulledSuggestion>[];
    for (final dc.Event e in result.data!) {
      if (e.eventId == null) continue;
      if (e.allDay ?? false) continue;
      final DateTime? start = e.start?.toLocal();
      final DateTime? end = e.end?.toLocal();
      if (start == null || end == null || !end.isAfter(start)) continue;
      if ((e.description ?? '').contains('Tracked in Tally')) continue;
      out.add(PulledSuggestion(
        eventId: e.eventId!,
        title: e.title?.trim().isNotEmpty ?? false
            ? e.title!.trim()
            : 'Untitled event',
        start: start,
        end: end,
      ));
    }
    out.sort((PulledSuggestion a, PulledSuggestion b) =>
        a.start.compareTo(b.start));
    return out;
  }

  static String _describe(dc.Result<Object?> result, String fallback) {
    if (result.errors.isEmpty) return fallback;
    return result.errors
        .map((dc.ResultError e) => e.errorMessage)
        .join('; ');
  }
}
