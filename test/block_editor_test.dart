import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tally/core/theme/organic_theme.dart';
import 'package:tally/data/db/database.dart';
import 'package:tally/data/prefs/settings_store.dart';
import 'package:tally/data/repositories/activity_repository.dart';
import 'package:tally/data/repositories/tracking_repository.dart';
import 'package:tally/domain/models.dart';
import 'package:tally/features/names/names_screen.dart';
import 'package:tally/providers.dart';

/// Drives the real Names screen over a real in-memory database, so the long
/// press, both sheets and the save all run through the repository.
void main() {
  late AppDatabase db;
  late TrackingRepository blocks;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    blocks = TrackingRepository(db, ActivityRepository(db));
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpNames(WidgetTester tester) async {
    final SettingsStore? store = await tester.runAsync(SettingsStore.open);
    await tester.pumpWidget(ProviderScope(
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
        settingsStoreProvider.overrideWithValue(store!),
      ],
      child: MaterialApp(
        theme: buildOrganicTheme(),
        home: const Scaffold(body: SafeArea(child: NamesScreen())),
      ),
    ));
    await settle(tester);
  }

  Future<void> tearDownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  }

  testWidgets('holding a name opens its blocks, and a description saves',
      (WidgetTester tester) async {
    final DateTime start = DateTime.now().subtract(const Duration(hours: 3));
    await tester.runAsync(() => blocks.addRetroactive(
          activityName: 'Deep work',
          start: start,
          end: start.add(const Duration(hours: 1)),
        ));
    await pumpNames(tester);

    expect(find.text('Hold a name to edit its time blocks'), findsOneWidget);

    await tester.longPress(find.text('Deep work'));
    await settle(tester);
    expect(find.text('Add a description'), findsOneWidget);

    await tester.tap(find.text('Add a description'));
    await settle(tester);
    expect(find.text('Edit block'), findsOneWidget);
    expect(find.text('That is '), findsNothing); // rich text, checked below
    expect(find.textContaining('1h 00m', findRichText: true), findsWidgets);

    await tester.enterText(
        find.byType(TextField).last, 'Outlined the sync chapter');
    // On a short screen the sheet scrolls; bring Save into view first.
    await tester.ensureVisible(find.text('Save changes'));
    await settle(tester);
    await tester.tap(find.text('Save changes'));
    await settle(tester);

    final List<TrackedBlock>? saved = await tester.runAsync(blocks.allBlocks);
    expect(saved!.single.note, 'Outlined the sync chapter');
    expect(saved.single.syncDirty, isTrue);

    // The edit sheet closed and the list underneath shows the description.
    expect(find.text('Edit block'), findsNothing);
    expect(find.text('Outlined the sync chapter'), findsOneWidget);

    await tearDownTree(tester);
  });

  testWidgets('a running block can be described but not re-timed',
      (WidgetTester tester) async {
    await tester.runAsync(() => blocks.start('Live'));
    await pumpNames(tester);

    await tester.longPress(find.text('Live'));
    await settle(tester);
    expect(find.text('Running'), findsOneWidget);

    await tester.tap(find.text('Add a description'));
    await settle(tester);
    expect(find.textContaining('still running'), findsOneWidget);

    // The start date button is inert, so no picker opens.
    await tester.tap(find.byIcon(LucideIcons.calendar).first);
    await settle(tester);
    expect(find.byType(DatePickerDialog), findsNothing);

    await tester.enterText(find.byType(TextField).last, 'Pairing on sync');
    // On a short screen the sheet scrolls; bring Save into view first.
    await tester.ensureVisible(find.text('Save changes'));
    await settle(tester);
    await tester.tap(find.text('Save changes'));
    await settle(tester);

    final TrackedBlock? running =
        await tester.runAsync<TrackedBlock?>(blocks.currentRunning);
    expect(running!.note, 'Pairing on sync');
    expect(running.isRunning, isTrue);

    await tearDownTree(tester);
  });

  testWidgets('holding a name while picking names to group does nothing',
      (WidgetTester tester) async {
    final DateTime start = DateTime.now().subtract(const Duration(hours: 3));
    await tester.runAsync(() => blocks.addRetroactive(
          activityName: 'Email',
          start: start,
          end: start.add(const Duration(minutes: 30)),
        ));
    await pumpNames(tester);

    await tester.tap(find.text('Group'));
    await settle(tester);
    await tester.longPress(find.text('Email'));
    await settle(tester);
    expect(find.text('Add a description'), findsNothing);

    await tearDownTree(tester);
  });
}

/// Fixed pumps rather than pumpAndSettle: a loading spinner would keep
/// pumpAndSettle waiting forever.
Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
