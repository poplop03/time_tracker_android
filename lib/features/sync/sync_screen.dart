import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/organic_theme.dart';
import '../../core/time/formatting.dart';
import '../../data/prefs/settings_store.dart';
import '../../providers.dart';
import '../../services/background_sync.dart';
import '../shell/widgets.dart';
import 'google_calendar_service.dart';

/// Four steps: intro, pick a calendar, choose a direction, then the connected
/// status card.
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  int _step = 0;
  bool _busy = false;
  String? _error;
  String? _account;
  List<CalendarChoice>? _calendars;
  String? _pickedId;
  String? _pickedName;
  String? _lastResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(settingsProvider).isConnected) setState(() => _step = 3);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Settings settings = ref.watch(settingsProvider);
    final int pending = ref.watch(pendingSyncCountProvider).value ?? 0;
    final int step = settings.isConnected && _step < 3 ? 3 : _step;

    return ScreenScaffold(
      title: 'Sync',
      kicker: settings.isConnected
          ? 'Connected'
          : 'Step ${step + 1} of 4',
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          sliver: SliverList.list(children: <Widget>[
            _StepDots(current: step),
            const SizedBox(height: 18),
            if (_error != null) ...<Widget>[
              _ErrorCard(message: _error!),
              const SizedBox(height: 16),
            ],
            switch (step) {
              0 => _IntroStep(busy: _busy, onConnect: _connect),
              1 => _CalendarStep(
                  calendars: _calendars ?? const <CalendarChoice>[],
                  busy: _busy,
                  pickedId: _pickedId,
                  onPick: (CalendarChoice c) => setState(() {
                    _pickedId = c.id;
                    _pickedName = c.name;
                  }),
                  onCreate: _createCalendar,
                  onNext: _pickedId == null
                      ? null
                      : () => setState(() => _step = 2),
                ),
              2 => _DirectionStep(
                  selected: settings.direction,
                  onSelected: (SyncDirection d) =>
                      ref.read(settingsProvider.notifier).setDirection(d),
                  onDone: _finish,
                ),
              _ => _ConnectedStep(
                  settings: settings,
                  account: _account,
                  pending: pending,
                  busy: _busy,
                  lastResult: _lastResult,
                  onSyncNow: _syncNow,
                  onDisconnect: _disconnect,
                ),
            },
          ]),
        ),
      ],
    );
  }

  Future<void> _guard(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on CalendarNotConfigured catch (e) {
      setState(() => _error = e.toString());
    } on CalendarAuthExpired catch (e) {
      setState(() => _error = e.toString());
    } on Exception catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() => _guard(() async {
        final GoogleCalendarService service =
            ref.read(calendarServiceProvider);
        _account = await service.connect();
        _calendars = await service.listCalendars();
        if (!mounted) return;
        setState(() => _step = 1);
      });

  Future<void> _createCalendar() => _guard(() async {
        final CalendarChoice created = await ref
            .read(calendarServiceProvider)
            .createDedicatedCalendar('Time tracked');
        if (!mounted) return;
        setState(() {
          _calendars = <CalendarChoice>[created, ...?_calendars];
          _pickedId = created.id;
          _pickedName = created.name;
        });
      });

  Future<void> _finish() async {
    if (_pickedId == null) return;
    await ref
        .read(settingsProvider.notifier)
        .setCalendar(_pickedId!, _pickedName ?? 'Calendar');
    await BackgroundSync.schedulePeriodic();
    if (!mounted) return;
    setState(() => _step = 3);
    await _syncNow();
  }

  Future<void> _syncNow() => _guard(() async {
        final Settings settings = ref.read(settingsProvider);
        final SyncOutcome outcome =
            await ref.read(syncEngineProvider).push(settings);
        if (outcome.error == 'reconnect') {
          await ref.read(settingsProvider.notifier).markNeedsReconnect();
          if (mounted) {
            setState(() => _error =
                'Google access expired — reconnect to keep syncing.');
          }
          return;
        }
        await ref.read(settingsProvider.notifier).markSynced();
        if (!mounted) return;
        setState(() {
          _lastResult = outcome.pushed == 0 && outcome.skipped == 0
              ? 'Nothing waiting to push.'
              : 'Pushed ${outcome.pushed} block'
                  '${outcome.pushed == 1 ? '' : 's'}'
                  '${outcome.skipped > 0 ? ', skipped ${outcome.skipped} short one${outcome.skipped == 1 ? '' : 's'}' : ''}.';
          _error = outcome.error != null && outcome.error != 'reconnect'
              ? outcome.error
              : null;
        });
      });

  Future<void> _disconnect() => _guard(() async {
        await BackgroundSync.cancel();
        await ref.read(calendarServiceProvider).disconnect();
        await ref.read(settingsProvider.notifier).disconnect();
        if (!mounted) return;
        setState(() {
          _step = 0;
          _calendars = null;
          _pickedId = null;
          _pickedName = null;
          _account = null;
          _lastResult = null;
        });
      });
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    return Row(
      children: <Widget>[
        for (int i = 0; i < 4; i++) ...<Widget>[
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: i <= current ? c.accent : c.neutral300,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          if (i < 3) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _IntroStep extends StatelessWidget {
  const _IntroStep({required this.busy, required this.onConnect});
  final bool busy;
  final Future<void> Function() onConnect;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    return OrganicCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(LucideIcons.calendar, size: 22, color: c.accent700),
          const SizedBox(height: 14),
          Text('Put your blocks on your calendar',
              style: context.texts.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Tally writes each finished block as an event on one calendar you '
            'choose. It never touches your other calendars, and it never '
            'creates blocks from your calendar without asking you first.',
            style: context.texts.bodyMedium,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : onConnect,
              icon: const Icon(LucideIcons.link, size: 16),
              label: Text(busy ? 'Connecting…' : 'Connect Google Calendar'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarStep extends StatelessWidget {
  const _CalendarStep({
    required this.calendars,
    required this.busy,
    required this.pickedId,
    required this.onPick,
    required this.onCreate,
    required this.onNext,
  });

  final List<CalendarChoice> calendars;
  final bool busy;
  final String? pickedId;
  final ValueChanged<CalendarChoice> onPick;
  final Future<void> Function() onCreate;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Which calendar?', style: context.texts.headlineMedium),
        const SizedBox(height: 4),
        Text('Everything Tally writes goes here and nowhere else.',
            style: context.texts.bodyMedium),
        const SizedBox(height: 16),
        OrganicCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: RadioGroup<String>(
            groupValue: pickedId,
            onChanged: (String? id) {
              if (id == null) return;
              onPick(calendars.firstWhere((CalendarChoice c) => c.id == id));
            },
            child: Column(
            children: <Widget>[
              for (final CalendarChoice choice in calendars)
                RadioListTile<String>(
                  value: choice.id,
                  activeColor: c.accent700,
                  title: Text(choice.name, style: context.texts.titleSmall),
                  subtitle: choice.primary
                      ? Text('Your main calendar',
                          style: context.texts.bodySmall)
                      : null,
                ),
              ListTile(
                onTap: busy ? null : onCreate,
                leading: Icon(LucideIcons.plus, size: 18, color: c.accent700),
                title: Text('Time tracked (new)',
                    style: context.texts.titleSmall),
                subtitle: Text('Create a dedicated calendar',
                    style: context.texts.bodySmall),
              ),
            ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: onNext, child: const Text('Continue')),
        ),
      ],
    );
  }
}

class _DirectionStep extends StatelessWidget {
  const _DirectionStep({
    required this.selected,
    required this.onSelected,
    required this.onDone,
  });

  final SyncDirection selected;
  final ValueChanged<SyncDirection> onSelected;
  final Future<void> Function() onDone;

  static const Map<SyncDirection, (String, String, IconData)> _options =
      <SyncDirection, (String, String, IconData)>{
    SyncDirection.push: (
      'Push only',
      'Tracked blocks become calendar events.',
      LucideIcons.arrowUp
    ),
    SyncDirection.pull: (
      'Pull only',
      'Calendar events are offered as blocks you confirm.',
      LucideIcons.arrowDown
    ),
    SyncDirection.both: (
      'Both ways',
      'Push your blocks, and suggest blocks from events.',
      LucideIcons.arrowUpDown
    ),
  };

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Which way should it flow?', style: context.texts.headlineMedium),
        const SizedBox(height: 16),
        for (final MapEntry<SyncDirection, (String, String, IconData)> e
            in _options.entries) ...<Widget>[
          InkWell(
            onTap: () => onSelected(e.key),
            borderRadius: OrganicRadii.card,
            child: OrganicCard(
              color: selected == e.key ? c.accent200 : c.surface,
              border: Border.all(
                color: selected == e.key ? c.accent400 : Colors.transparent,
                width: 2,
              ),
              child: Row(
                children: <Widget>[
                  Icon(e.value.$3, size: 20, color: c.accent700),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(e.value.$1, style: context.texts.titleMedium),
                        const SizedBox(height: 2),
                        Text(e.value.$2, style: context.texts.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: onDone, child: const Text('Finish setup')),
        ),
      ],
    );
  }
}

class _ConnectedStep extends ConsumerWidget {
  const _ConnectedStep({
    required this.settings,
    required this.account,
    required this.pending,
    required this.busy,
    required this.lastResult,
    required this.onSyncNow,
    required this.onDisconnect,
  });

  final Settings settings;
  final String? account;
  final int pending;
  final bool busy;
  final String? lastResult;
  final Future<void> Function() onSyncNow;
  final Future<void> Function() onDisconnect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final OrganicColors c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        OrganicCard(
          color: settings.needsReconnect ? c.accent200 : c.sage100,
          border: Border.all(
              color: settings.needsReconnect ? c.accent400 : c.sage300),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    settings.needsReconnect
                        ? LucideIcons.unlink
                        : LucideIcons.check,
                    size: 18,
                    color: settings.needsReconnect ? c.accent800 : c.sage800,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    settings.needsReconnect
                        ? 'Reconnect required'
                        : 'Syncing to ${settings.calendarName}',
                    style: context.texts.titleMedium?.copyWith(
                      color: settings.needsReconnect ? c.accent900 : c.sage800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                settings.lastSyncAt == null
                    ? 'Not synced yet.'
                    : 'Last sync ${formatClock(settings.lastSyncAt!, settings.use24h)}.',
                style: context.texts.bodyMedium?.copyWith(
                  color: settings.needsReconnect ? c.accent800 : c.sage800,
                ),
              ),
              Text(
                '$pending block${pending == 1 ? '' : 's'} waiting to push.',
                style: context.texts.bodyMedium?.copyWith(
                  color: settings.needsReconnect ? c.accent800 : c.sage800,
                ),
              ),
              if (account != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(account!, style: context.texts.bodySmall),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        OrganicCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            children: <Widget>[
              SwitchListTile(
                value: settings.onlyLongBlocks,
                activeThumbColor: c.accent700,
                onChanged: (bool v) =>
                    ref.read(settingsProvider.notifier).setOnlyLongBlocks(v),
                title: Text('Only sync blocks over 15 minutes',
                    style: context.texts.titleSmall),
              ),
              SwitchListTile(
                value: settings.includeActivityName,
                activeThumbColor: c.accent700,
                onChanged: (bool v) => ref
                    .read(settingsProvider.notifier)
                    .setIncludeActivityName(v),
                title: Text('Include activity name in event title',
                    style: context.texts.titleSmall),
                subtitle: Text(
                  settings.includeActivityName
                      ? 'Events are titled with the activity.'
                      : 'Events are titled with the group instead.',
                  style: context.texts.bodySmall,
                ),
              ),
              SwitchListTile(
                value: settings.use24h,
                activeThumbColor: c.accent700,
                onChanged: (bool v) =>
                    ref.read(settingsProvider.notifier).setUse24h(v),
                title: Text('24-hour clock', style: context.texts.titleSmall),
              ),
            ],
          ),
        ),
        if (lastResult != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(lastResult!, style: context.texts.bodyMedium),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: busy ? null : onSyncNow,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: Text(busy ? 'Syncing…' : 'Sync now'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: busy ? null : onDisconnect,
            icon: const Icon(LucideIcons.logOut, size: 16),
            label: const Text('Disconnect'),
          ),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    return OrganicCard(
      color: c.accent200,
      border: Border.all(color: c.accent400),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(LucideIcons.x, size: 18, color: c.accent800),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message,
                style: context.texts.bodyMedium?.copyWith(color: c.accent900)),
          ),
        ],
      ),
    );
  }
}
