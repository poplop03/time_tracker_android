import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';
import 'data/db/database.dart';
import 'data/prefs/settings_store.dart';
import 'providers.dart';
import 'services/background_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fonts ship inside the APK; never reach for the network.
  GoogleFonts.config.allowRuntimeFetching = false;
  LicenseRegistry.addLicense(() async* {
    final String license =
        await rootBundle.loadString('google_fonts/Comfortaa-OFL.txt');
    yield LicenseEntryWithLineBreaks(<String>['Comfortaa'], license);
  });

  FlutterForegroundTask.initCommunicationPort();

  final AppDatabase database = AppDatabase();
  final SettingsStore settings = await SettingsStore.open();
  await BackgroundSync.initialize();

  runApp(
    ProviderScope(
      overrides: <Override>[
        databaseProvider.overrideWithValue(database),
        settingsStoreProvider.overrideWithValue(settings),
      ],
      child: const TallyApp(),
    ),
  );
}
