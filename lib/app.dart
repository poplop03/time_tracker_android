import 'package:flutter/material.dart';

import 'core/theme/organic_theme.dart';
import 'features/shell/app_shell.dart';

class TallyApp extends StatelessWidget {
  const TallyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tally',
      debugShowCheckedModeBanner: false,
      theme: buildOrganicTheme(),
      home: const AppShell(),
    );
  }
}
