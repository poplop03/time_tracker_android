import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/organic_theme.dart';
import '../../providers.dart';
import '../insights/insights_screen.dart';
import '../names/names_screen.dart';
import '../stats/stats_screen.dart';
import '../sync/sync_screen.dart';
import '../today/today_screen.dart';
import '../today/tracking_actions.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  int _index = 0;

  static const List<({String label, IconData icon})> _tabs =
      <({String label, IconData icon})>[
    (label: 'Today', icon: LucideIcons.clock),
    (label: 'Stats', icon: LucideIcons.chartColumn),
    (label: 'Insights', icon: LucideIcons.lightbulb),
    (label: 'Names', icon: LucideIcons.tag),
    (label: 'Sync', icon: LucideIcons.refreshCw),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final TrackingActions actions = ref.read(trackingActionsProvider);
      ref.read(timerServiceProvider).init();
      await ref.read(timerServiceProvider).requestPermissions();
      await actions.reconcile();
      await _checkCalendarAccess();
    });
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A Stop tapped on the notification while the app was backgrounded.
    if (state == AppLifecycleState.resumed) {
      ref.read(trackingActionsProvider).reconcile();
      ref.read(settingsProvider.notifier).reload();
    }
  }

  /// A connected calendar is only useful while the permission holds — the user
  /// can revoke it in Android settings at any time. Check quietly on start and
  /// say so on the Sync tab rather than failing at the next push.
  Future<void> _checkCalendarAccess() async {
    if (!ref.read(settingsProvider).isConnected) return;
    final bool granted =
        await ref.read(calendarServiceProvider).hasPermission();
    if (!mounted || granted) return;
    await ref.read(settingsProvider.notifier).markNeedsReconnect();
  }

  void _onTaskData(Object data) {
    if (data is Map && data['stopAtMs'] is int) {
      final DateTime at =
          DateTime.fromMillisecondsSinceEpoch(data['stopAtMs'] as int);
      ref.read(trackingActionsProvider).stop(at: at);
    }
  }

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _index,
          children: const <Widget>[
            TodayScreen(),
            StatsScreen(),
            InsightsScreen(),
            NamesScreen(),
            SyncScreen(),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.neutral300)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: <Widget>[
                for (int i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: _index == i,
                      label: _tabs[i].label,
                      child: InkWell(
                        onTap: () {
                          setState(() => _index = i);
                          ref.read(selectedTabProvider.notifier).select(i);
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(
                              _tabs[i].icon,
                              size: 20,
                              color: _index == i ? c.accent700 : c.neutral600,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _tabs[i].label,
                              style: context.texts.bodySmall?.copyWith(
                                fontSize: 11,
                                color: _index == i ? c.accent700 : c.neutral600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
