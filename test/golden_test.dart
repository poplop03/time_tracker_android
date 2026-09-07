import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tally/core/theme/organic_theme.dart';
import 'package:tally/core/time/day.dart';
import 'package:tally/data/prefs/settings_store.dart';
import 'package:tally/domain/models.dart';
import 'package:tally/features/insights/insights_screen.dart';
import 'package:tally/features/names/names_screen.dart';
import 'package:tally/features/stats/stats_screen.dart';
import 'package:tally/features/sync/sync_screen.dart';
import 'package:tally/features/today/today_screen.dart';
import 'package:tally/providers.dart';

/// Fixed clock so every golden is reproducible.
final DateTime _now = startOfDay(DateTime.now()).add(const Duration(hours: 14, minutes: 32));

TrackedBlock _block({
  required int id,
  required String name,
  String? group,
  required int startHour,
  int startMinute = 0,
  int? endHour,
  int endMinute = 0,
  bool synced = false,
}) {
  return TrackedBlock(
    id: id,
    activityId: id,
    activityName: name,
    groupName: group,
    colorSeed: id,
    startedAt: startOfDay(_now).add(Duration(hours: startHour, minutes: startMinute)),
    endedAt: endHour == null
        ? null
        : startOfDay(_now).add(Duration(hours: endHour, minutes: endMinute)),
    calendarEventId: synced ? 'evt$id' : null,
    syncDirty: !synced,
  );
}

final List<TrackedBlock> _todayBlocks = <TrackedBlock>[
  _block(id: 1, name: 'Deep work', group: 'Work', startHour: 9, endHour: 10, endMinute: 40, synced: true),
  _block(id: 2, name: 'Standup', group: 'Work', startHour: 11, endHour: 11, endMinute: 20),
  _block(id: 3, name: 'Lunch', group: 'Life', startHour: 13, endHour: 13, endMinute: 45),
  _block(id: 4, name: 'Code review', group: 'Work', startHour: 14, startMinute: 10),
];

final List<ActivitySummary> _activities = <ActivitySummary>[
  const ActivitySummary(id: 1, name: 'Deep work', groupName: 'Work', colorSeed: 1, total: Duration(hours: 12), blockCount: 9),
  const ActivitySummary(id: 2, name: 'Standup', groupName: 'Work', colorSeed: 2, total: Duration(hours: 2), blockCount: 8),
  const ActivitySummary(id: 3, name: 'Lunch', groupName: 'Life', colorSeed: 3, total: Duration(hours: 4), blockCount: 6),
  const ActivitySummary(id: 4, name: 'Reading', groupName: null, colorSeed: 4, total: Duration(hours: 3), blockCount: 4),
];

final List<GroupSlice> _slices = <GroupSlice>[
  const GroupSlice(group: 'Work', total: Duration(hours: 14), percent: 67, colorSeed: 1),
  const GroupSlice(group: 'Life', total: Duration(hours: 4), percent: 19, colorSeed: 3),
  const GroupSlice(group: kUngrouped, total: Duration(hours: 3), percent: 14, colorSeed: 4),
];

List<DayTotal> _weekTotals() {
  const List<int> minutes = <int>[320, 415, 180, 470, 260, 90, 392];
  final List<DateTime> days = lastDays(_now, 7);
  return <DayTotal>[
    for (int i = 0; i < 7; i++)
      DayTotal(day: days[i], total: Duration(minutes: minutes[i])),
  ];
}

final InsightSet _insights = InsightSet(
  averageTrackedDay: const Duration(hours: 5, minutes: 18),
  longestStretch: const Duration(hours: 3, minutes: 25),
  longestStretchDay: DateTime(2026, 9, 2),
  untrackedShare: 47,
  byHour: <Duration>[
    for (int h = 0; h < 24; h++)
      Duration(minutes: h < 7 || h > 21 ? 0 : (h * 13) % 90),
  ],
  observation: 'You do your most tracked work around 10am, and you average '
      '5h 18m a day.',
  daysWithData: 21,
);

Future<Widget> _host(
  Widget child, {
  List<Override> extra = const <Override>[],
  Map<String, Object> prefs = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final SettingsStore store = await SettingsStore.open();
  return ProviderScope(
    overrides: <Override>[
      settingsStoreProvider.overrideWithValue(store),
      tickerProvider.overrideWith((Ref ref) => Stream<DateTime>.value(_now)),
      runningBlockProvider.overrideWith(
          (Ref ref) => Stream<TrackedBlock?>.value(_todayBlocks.last)),
      todayBlocksProvider.overrideWith(
          (Ref ref) => Stream<List<TrackedBlock>>.value(_todayBlocks)),
      activitiesProvider.overrideWith(
          (Ref ref) => Stream<List<ActivitySummary>>.value(_activities)),
      groupsProvider.overrideWith(
          (Ref ref) => Stream<List<String>>.value(<String>['Life', 'Work'])),
      pendingSyncCountProvider.overrideWith((Ref ref) => Stream<int>.value(3)),
      weekBlocksProvider.overrideWith(
          (Ref ref) => Stream<List<TrackedBlock>>.value(_todayBlocks)),
      insightWindowProvider.overrideWith(
          (Ref ref) => Stream<List<TrackedBlock>>.value(_todayBlocks)),
      weekTotalsProvider.overrideWithValue(_weekTotals()),
      weekBreakdownProvider.overrideWithValue(_slices),
      insightsProvider.overrideWithValue(_insights),
      ...extra,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildOrganicTheme(),
      home: Scaffold(body: SafeArea(child: child)),
    ),
  );
}

Future<void> _pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Map<String, Object> prefs = const <String, Object>{},
}) async {
  tester.view.physicalSize = const Size(1080, 2160);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await _host(screen, prefs: prefs));
  await tester.pump(const Duration(milliseconds: 50));
}

/// flutter_test does not pull package icon fonts out of the asset bundle, so
/// load Lucide by hand — otherwise every icon lands in the golden as a box.
Future<void> _loadLucide() async {
  final File file = File(
      '${Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache'}'
      '/hosted/pub.dev/lucide_icons_flutter-3.1.19/assets/lucide.ttf');
  if (!file.existsSync()) return;
  final FontLoader loader =
      FontLoader('packages/lucide_icons_flutter/Lucide')
    ..addFont(Future<ByteData>.value(
        ByteData.sublistView(file.readAsBytesSync())));
  await loader.load();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadLucide();
  });

  testWidgets('Today', (WidgetTester tester) async {
    await _pumpScreen(tester, const TodayScreen());
    await expectLater(find.byType(TodayScreen),
        matchesGoldenFile('goldens/today.png'));
  });

  testWidgets('Stats', (WidgetTester tester) async {
    await _pumpScreen(tester, const StatsScreen());
    await expectLater(find.byType(StatsScreen),
        matchesGoldenFile('goldens/stats.png'));
  });

  testWidgets('Insights', (WidgetTester tester) async {
    await _pumpScreen(tester, const InsightsScreen());
    await expectLater(find.byType(InsightsScreen),
        matchesGoldenFile('goldens/insights.png'));
  });

  testWidgets('Names', (WidgetTester tester) async {
    await _pumpScreen(tester, const NamesScreen());
    await expectLater(find.byType(NamesScreen),
        matchesGoldenFile('goldens/names.png'));
  });

  testWidgets('Sync', (WidgetTester tester) async {
    await _pumpScreen(tester, const SyncScreen());
    await expectLater(find.byType(SyncScreen),
        matchesGoldenFile('goldens/sync.png'));
  });

  testWidgets('Sync, connected', (WidgetTester tester) async {
    await _pumpScreen(tester, const SyncScreen(), prefs: <String, Object>{
      'calendarId': 'cal-1',
      'calendarName': 'Time tracked',
      'accountEmail': 'you@example.com',
      'lastSyncAt': _now.millisecondsSinceEpoch,
    });
    // The connected card is reached via a post-frame callback.
    await tester.pump(const Duration(milliseconds: 50));
    await expectLater(find.byType(SyncScreen),
        matchesGoldenFile('goldens/sync_connected.png'));
  });
}
