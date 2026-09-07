import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tally/data/prefs/settings_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('a fresh install is not connected and has no account', () async {
    final Settings s = (await SettingsStore.open()).read();
    expect(s.isConnected, isFalse);
    expect(s.accountEmail, isNull);
    expect(s.needsReconnect, isFalse);
  });

  test('the calendar account survives a restart', () async {
    final SettingsStore store = await SettingsStore.open();
    await store.write(store.read().copyWith(
          calendarId: 'cal-1',
          calendarName: 'Work',
          accountEmail: 'someone@example.com',
        ));

    final Settings reopened = (await SettingsStore.open()).read();
    expect(reopened.accountEmail, 'someone@example.com');
    expect(reopened.calendarName, 'Work');
    expect(reopened.isConnected, isTrue);
  });

  test('stopping sync clears the account along with the calendar', () async {
    final SettingsStore store = await SettingsStore.open();
    await store.write(store.read().copyWith(
          calendarId: 'cal-1',
          accountEmail: 'someone@example.com',
        ));
    await store.write(store.read().copyWith(clearCalendar: true));

    final Settings after = (await SettingsStore.open()).read();
    expect(after.accountEmail, isNull);
    expect(after.calendarId, isNull);
    expect(after.isConnected, isFalse);
  });

  test('sync preferences round-trip', () async {
    final SettingsStore store = await SettingsStore.open();
    await store.write(store.read().copyWith(
          use24h: true,
          direction: SyncDirection.both,
          onlyLongBlocks: false,
          includeActivityName: false,
        ));

    final Settings s = (await SettingsStore.open()).read();
    expect(s.use24h, isTrue);
    expect(s.direction, SyncDirection.both);
    expect(s.onlyLongBlocks, isFalse);
    expect(s.includeActivityName, isFalse);
  });
}
