import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:googleapis_auth/googleapis_auth.dart' as gauth;

import '../../domain/models.dart';

/// OAuth client id for this build. Supply it at build time:
///   `flutter build apk --dart-define=GOOGLE_SERVER_CLIENT_ID=…`
/// Without it, Google sign-in cannot start on Android and the Sync tab says so
/// instead of failing with a raw platform error.
const String kGoogleServerClientId =
    String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

const List<String> kCalendarScopes = <String>[
  gcal.CalendarApi.calendarEventsScope,
  gcal.CalendarApi.calendarReadonlyScope,
];

class CalendarNotConfigured implements Exception {
  @override
  String toString() =>
      'This build has no Google OAuth client id, so Calendar sync is off. '
      'Rebuild with --dart-define=GOOGLE_SERVER_CLIENT_ID=… to enable it.';
}

class CalendarAuthExpired implements Exception {
  @override
  String toString() => 'Google access expired — reconnect to keep syncing.';
}

/// A calendar the user can pick in step 1 of setup.
class CalendarChoice {
  const CalendarChoice({required this.id, required this.name, this.primary = false});
  final String id;
  final String name;
  final bool primary;
}

/// What one push run did.
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

/// Owns Google auth and every Calendar call. Only ever touches the calendar
/// whose id it is handed.
class GoogleCalendarService {
  bool _initialised = false;
  GoogleSignInAccount? _account;

  bool get isConfigured => kGoogleServerClientId.isNotEmpty;

  Future<void> _ensureInitialised() async {
    if (!isConfigured) throw CalendarNotConfigured();
    if (_initialised) return;
    await GoogleSignIn.instance
        .initialize(serverClientId: kGoogleServerClientId);
    _initialised = true;
  }

  /// Silent re-auth on app start and on background runs. Returns the signed-in
  /// address, or null when the user has to sign in again.
  Future<String?> restore() async {
    if (!isConfigured) return null;
    try {
      await _ensureInitialised();
      _account = await GoogleSignIn.instance.attemptLightweightAuthentication();
      return _account?.email;
    } on Exception {
      return null;
    }
  }

  /// Interactive connect, used by the Sync tab's step 0. Always puts the Google
  /// account picker in front of the user — signing in is what makes syncing
  /// possible, so it is never skipped — and then asks for calendar consent.
  /// Throws if the user backs out of either step, so a half-finished sign-in
  /// never reads as connected.
  Future<String> connect() async {
    await _ensureInitialised();
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw CalendarNotConfigured();
    }
    final GoogleSignInAccount account =
        await GoogleSignIn.instance.authenticate(scopeHint: kCalendarScopes);
    _account = account;

    // Consent to the calendar scopes, without which every API call would fail.
    final GoogleSignInClientAuthorization authorization =
        await account.authorizationClient.authorizeScopes(kCalendarScopes);
    // Touching the token here surfaces a refused grant now rather than at the
    // first sync.
    authorization.authClient(scopes: kCalendarScopes).close();
    return account.email;
  }

  /// Whether a Google session is still available without prompting.
  Future<bool> get isSignedIn async =>
      _account != null || (await restore()) != null;

  /// Signs out and revokes the grant, so the next connect starts from the
  /// account picker again.
  Future<void> disconnect() async {
    _account = null;
    if (!_initialised) return;
    await GoogleSignIn.instance.disconnect();
    await GoogleSignIn.instance.signOut();
  }

  String? get accountEmail => _account?.email;

  Future<gcal.CalendarApi> _api({bool interactive = false}) async {
    await _ensureInitialised();
    GoogleSignInAccount? account = _account;
    account ??= await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (account == null) throw CalendarAuthExpired();
    _account = account;

    GoogleSignInClientAuthorization? authorization =
        await account.authorizationClient.authorizationForScopes(kCalendarScopes);
    if (authorization == null) {
      if (!interactive) throw CalendarAuthExpired();
      authorization =
          await account.authorizationClient.authorizeScopes(kCalendarScopes);
    }
    final gauth.AuthClient client =
        authorization.authClient(scopes: kCalendarScopes);
    return gcal.CalendarApi(client);
  }

  Future<List<CalendarChoice>> listCalendars() async {
    final gcal.CalendarApi api = await _api(interactive: true);
    final gcal.CalendarList list = await api.calendarList.list();
    return <CalendarChoice>[
      for (final gcal.CalendarListEntry e in list.items ?? <gcal.CalendarListEntry>[])
        if (e.id != null &&
            (e.accessRole == 'owner' || e.accessRole == 'writer'))
          CalendarChoice(
            id: e.id!,
            name: e.summary ?? e.id!,
            primary: e.primary ?? false,
          ),
    ];
  }

  /// Creates the dedicated "Time tracked" calendar offered in step 1.
  Future<CalendarChoice> createDedicatedCalendar(String name) async {
    final gcal.CalendarApi api = await _api(interactive: true);
    final gcal.Calendar created = await api.calendars.insert(
      gcal.Calendar(summary: name, description: 'Blocks tracked in Tally'),
    );
    return CalendarChoice(id: created.id!, name: created.summary ?? name);
  }

  /// Pushes one block. Returns the calendar event id.
  Future<String> pushBlock({
    required String calendarId,
    required TrackedBlock block,
    required bool includeActivityName,
  }) async {
    final gcal.CalendarApi api = await _api();
    final String summary =
        includeActivityName ? block.activityName : block.group;
    final gcal.Event event = gcal.Event(
      summary: summary,
      description: 'Tracked in Tally',
      start: gcal.EventDateTime(
        dateTime: block.startedAt,
        timeZone: block.startedAt.timeZoneName,
      ),
      end: gcal.EventDateTime(
        dateTime: block.endedAt,
        timeZone: block.startedAt.timeZoneName,
      ),
    );

    final String? existing = block.calendarEventId;
    if (existing != null) {
      final gcal.Event patched =
          await api.events.patch(event, calendarId, existing);
      return patched.id ?? existing;
    }
    final gcal.Event inserted = await api.events.insert(event, calendarId);
    return inserted.id!;
  }

  /// Events in [from, to) that could become blocks. All-day and declined
  /// events are skipped; nothing is written to the database here.
  Future<List<PulledSuggestion>> pullSuggestions({
    required String calendarId,
    required DateTime from,
    required DateTime to,
  }) async {
    final gcal.CalendarApi api = await _api();
    final gcal.Events events = await api.events.list(
      calendarId,
      singleEvents: true,
      orderBy: 'startTime',
      timeMin: from.toUtc(),
      timeMax: to.toUtc(),
      maxResults: 250,
    );

    final List<PulledSuggestion> out = <PulledSuggestion>[];
    for (final gcal.Event e in events.items ?? <gcal.Event>[]) {
      final DateTime? start = e.start?.dateTime?.toLocal();
      final DateTime? end = e.end?.dateTime?.toLocal();
      if (start == null || end == null) continue; // all-day
      if (!end.isAfter(start)) continue;
      final bool declined = (e.attendees ?? <gcal.EventAttendee>[]).any(
          (gcal.EventAttendee a) =>
              (a.self ?? false) && a.responseStatus == 'declined');
      if (declined) continue;
      if ((e.description ?? '').contains('Tracked in Tally')) continue;
      out.add(PulledSuggestion(
        eventId: e.id ?? '${start.millisecondsSinceEpoch}',
        title: e.summary ?? 'Untitled event',
        start: start,
        end: end,
      ));
    }
    return out;
  }
}
