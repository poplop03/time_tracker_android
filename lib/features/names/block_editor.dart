import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/organic_theme.dart';
import '../../core/time/day.dart';
import '../../core/time/formatting.dart';
import '../../data/prefs/settings_store.dart';
import '../../data/repositories/tracking_repository.dart';
import '../../domain/block_edit.dart';
import '../../domain/models.dart';
import '../../providers.dart';
import '../../services/background_sync.dart';
import '../shell/widgets.dart';

/// Every block tracked under one name, newest first. Opened by holding a name
/// on the Names tab; tapping a block opens [BlockEditSheet].
class ActivityBlocksSheet extends ConsumerStatefulWidget {
  const ActivityBlocksSheet({super.key, required this.activity});

  final ActivitySummary activity;

  static Future<void> show(BuildContext context, ActivitySummary activity) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext _) => ActivityBlocksSheet(activity: activity),
    );
  }

  @override
  ConsumerState<ActivityBlocksSheet> createState() =>
      _ActivityBlocksSheetState();
}

class _ActivityBlocksSheetState extends ConsumerState<ActivityBlocksSheet> {
  static const int _pageSize = 30;

  int _limit = _pageSize;

  // Kept while a wider page loads, so "Show earlier blocks" does not blank
  // the list for a frame.
  List<TrackedBlock> _shown = const <TrackedBlock>[];
  bool _loadedOnce = false;

  @override
  Widget build(BuildContext context) {
    final DateTime now = ref.watch(clockProvider)();
    final bool use24h = ref.watch(settingsProvider).use24h;

    // Follow the live summary so the header total moves as blocks are edited.
    ActivitySummary activity = widget.activity;
    for (final ActivitySummary a
        in ref.watch(activitiesProvider).value ?? const <ActivitySummary>[]) {
      if (a.id == widget.activity.id) {
        activity = a;
        break;
      }
    }

    final List<TrackedBlock>? page =
        ref.watch(activityBlocksProvider((activity.id, _limit))).value;
    if (page != null) {
      _shown = page;
      _loadedOnce = true;
    }
    final bool mayHaveEarlier = page != null && page.length >= _limit;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController scroll) {
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: <Widget>[
            const _SheetHandle(),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                ActivityDot(activity.colorSeed, size: 12),
                const SizedBox(width: 10),
                Expanded(
                  child:
                      Text(activity.name, style: context.texts.headlineMedium),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${formatDurationOrDash(activity.total)}  ·  '
              '${activity.blockCount} block'
              '${activity.blockCount == 1 ? '' : 's'}  ·  ${activity.group}',
              style: context.texts.bodySmall,
            ),
            const SizedBox(height: 14),
            Text(
              'Tap a block to change when it started and ended, or to '
              'describe what you did.',
              style: context.texts.bodyMedium,
            ),
            const SizedBox(height: 18),
            if (!_loadedOnce)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_shown.isEmpty)
              EmptyNote(
                icon: LucideIcons.clock,
                title: 'Nothing tracked yet',
                body: 'Blocks you track as “${activity.name}” will show up '
                    'here, ready to edit.',
              )
            else
              for (final TrackedBlock block in _shown) ...<Widget>[
                _BlockTile(
                  block: block,
                  now: now,
                  use24h: use24h,
                  onTap: () => BlockEditSheet.show(context, block),
                ),
                const SizedBox(height: 10),
              ],
            if (mayHaveEarlier)
              Center(
                child: TextButton.icon(
                  onPressed: () => setState(() => _limit += _pageSize),
                  icon: const Icon(LucideIcons.chevronDown, size: 16),
                  label: const Text('Show earlier blocks'),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BlockTile extends StatelessWidget {
  const _BlockTile({
    required this.block,
    required this.now,
    required this.use24h,
    required this.onTap,
  });

  final TrackedBlock block;
  final DateTime now;
  final bool use24h;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    return Material(
      color: c.surface,
      borderRadius: OrganicRadii.row,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      formatDayLabel(block.startedAt, now),
                      style: context.texts.titleSmall,
                    ),
                  ),
                  if (block.isRunning)
                    GroupPill(
                      'Running',
                      color: c.accent800,
                      background: c.accent200,
                    )
                  else
                    Text(
                      formatDuration(block.duration),
                      style: context.texts.titleSmall,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                formatSpan(block.startedAt, block.endedAt, use24h),
                style: context.texts.bodySmall,
              ),
              const SizedBox(height: 10),
              if (block.note != null)
                Text(
                  block.note!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyMedium?.copyWith(color: c.text),
                )
              else
                Row(
                  children: <Widget>[
                    Icon(LucideIcons.pencil, size: 13, color: c.accent700),
                    const SizedBox(width: 6),
                    Text(
                      'Add a description',
                      style:
                          context.texts.bodySmall?.copyWith(color: c.accent700),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Changes one block's start, end and description. A running block can be
/// described, but its times stay locked until the timer is stopped.
class BlockEditSheet extends ConsumerStatefulWidget {
  const BlockEditSheet({super.key, required this.block});

  final TrackedBlock block;

  static Future<void> show(BuildContext context, TrackedBlock block) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext _) => BlockEditSheet(block: block),
    );
  }

  @override
  ConsumerState<BlockEditSheet> createState() => _BlockEditSheetState();
}

class _BlockEditSheetState extends ConsumerState<BlockEditSheet> {
  late DateTime _start = widget.block.startedAt;
  late DateTime? _end = widget.block.endedAt;
  late final TextEditingController _note =
      TextEditingController(text: widget.block.note ?? '');
  bool _saving = false;

  /// Why the repository refused the last save; cleared by any change.
  String? _rejection;

  bool get _running => widget.block.isRunning;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String? _problem(DateTime now) => _running || _end == null
      ? null
      : blockTimesProblem(start: _start, end: _end!, now: now);

  Future<void> _pickDate({required bool isStart}) async {
    final DateTime now = ref.read(clockProvider)();
    final DateTime current = isStart ? _start : _end!;
    final DateTime earliest = DateTime(now.year - 5);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: current.isAfter(now) ? now : current,
      firstDate: current.isBefore(earliest) ? current : earliest,
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    final DateTime moved = DateTime(picked.year, picked.month, picked.day,
        current.hour, current.minute, current.second);
    setState(() {
      if (isStart) {
        _start = moved;
      } else {
        _end = moved;
      }
      _rejection = null;
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final bool use24h = ref.read(settingsProvider).use24h;
    final DateTime current = isStart ? _start : _end!;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: use24h),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final DateTime moved = DateTime(
        current.year, current.month, current.day, picked.hour, picked.minute);
    setState(() {
      if (isStart) {
        _start = moved;
      } else {
        _end = moved;
      }
      _rejection = null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _rejection = null;
    });
    try {
      final BlockPlacement result =
          await ref.read(trackingRepositoryProvider).editBlock(
                id: widget.block.id,
                start: _start,
                end: _end,
                note: _note.text,
              );

      // An edited block that was already on the calendar should not wait for
      // the next periodic run to be corrected there.
      final Settings settings = ref.read(settingsProvider);
      if (settings.isConnected && settings.direction != SyncDirection.pull) {
        await BackgroundSync.pushNow();
      }

      if (!mounted) return;
      final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      final String? notice = _placementNotice(result);
      if (notice != null) {
        messenger
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(notice)));
      }
    } on OverlapRejected catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _rejection = e.message;
      });
    }
  }

  static String? _placementNotice(BlockPlacement p) {
    if (p.trimmed == 0 && p.removed == 0) return null;
    final List<String> parts = <String>[
      if (p.trimmed > 0)
        'trimmed ${p.trimmed} overlapping block${p.trimmed == 1 ? '' : 's'}',
      if (p.removed > 0)
        'replaced ${p.removed} it now covers',
    ];
    return 'Saved — ${parts.join(', ')}.';
  }

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    final DateTime now = ref.watch(clockProvider)();
    final bool use24h = ref.watch(settingsProvider).use24h;
    final String? problem = _problem(now);
    final String? shown = _rejection ?? problem;
    final Duration duration = (_end ?? now).difference(_start);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _SheetHandle(),
            const SizedBox(height: 18),
            Text('Edit block', style: context.texts.headlineMedium),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                ActivityDot(widget.block.colorSeed),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.block.activityName,
                      style: context.texts.bodyMedium),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_running) ...<Widget>[
              OrganicCard(
                color: c.accent200,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(LucideIcons.timer, size: 18, color: c.accent800),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This timer is still running. Stop it to change its '
                        'times — you can describe it now.',
                        style: context.texts.bodyMedium
                            ?.copyWith(color: c.accent900),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            _TimeField(
              label: 'Started',
              value: _start,
              now: now,
              use24h: use24h,
              onDate: _running ? null : () => _pickDate(isStart: true),
              onTime: _running ? null : () => _pickTime(isStart: true),
            ),
            const SizedBox(height: 10),
            if (_end != null)
              _TimeField(
                label: 'Ended',
                value: _end!,
                now: now,
                use24h: use24h,
                onDate: () => _pickDate(isStart: false),
                onTime: () => _pickTime(isStart: false),
              )
            else
              OrganicCard(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Ended', style: context.texts.bodySmall),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Icon(LucideIcons.timer, size: 15, color: c.neutral600),
                        const SizedBox(width: 8),
                        Text('Still running', style: context.texts.titleSmall),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            OrganicCard(
              color: c.accent200,
              border: shown == null
                  ? null
                  : Border.all(color: c.accent700, width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: <Widget>[
                  Icon(
                    shown == null ? LucideIcons.hourglass : LucideIcons.circleAlert,
                    size: 18,
                    color: c.accent800,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: shown == null
                        ? Text.rich(
                            TextSpan(
                              children: <InlineSpan>[
                                TextSpan(
                                  text: _running ? 'Running for ' : 'That is ',
                                  style: context.texts.bodyMedium
                                      ?.copyWith(color: c.accent800),
                                ),
                                TextSpan(
                                  text: formatDuration(duration),
                                  style: context.texts.titleMedium
                                      ?.copyWith(color: c.accent900),
                                ),
                              ],
                            ),
                          )
                        : Text(
                            shown,
                            style: context.texts.bodyMedium
                                ?.copyWith(color: c.accent900),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Description', style: context.texts.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              minLines: 3,
              maxLines: 6,
              maxLength: 500,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (_rejection != null) setState(() => _rejection = null);
              },
              decoration: InputDecoration(
                hintText: 'What did you do in this block?',
                counterText: '',
                contentPadding: const EdgeInsets.all(18),
                border: const OutlineInputBorder(
                  borderRadius: OrganicRadii.row,
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: OrganicRadii.row,
                  borderSide: BorderSide(color: c.neutral300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: OrganicRadii.row,
                  borderSide: BorderSide(color: c.accent700, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving || problem != null ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled date + time pair. Both buttons go inert when [onDate] and
/// [onTime] are null, which is how a running block's start stays locked.
class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.now,
    required this.use24h,
    this.onDate,
    this.onTime,
  });

  final String label;
  final DateTime value;
  final DateTime now;
  final bool use24h;
  final VoidCallback? onDate;
  final VoidCallback? onTime;

  @override
  Widget build(BuildContext context) {
    final String date = formatShortDate(value, now);
    final String time = formatClock(value, use24h);
    return OrganicCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: context.texts.bodySmall),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: _PickerButton(
                  icon: LucideIcons.calendar,
                  text: date,
                  semanticLabel: '$label date, $date',
                  onTap: onDate,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 132,
                child: _PickerButton(
                  icon: LucideIcons.clock,
                  text: time,
                  semanticLabel: '$label time, $time',
                  onTap: onTime,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PickerButton extends StatelessWidget {
  const _PickerButton({
    required this.icon,
    required this.text,
    required this.semanticLabel,
    this.onTap,
  });

  final IconData icon;
  final String text;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    final bool enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: c.neutral200,
        shape: StadiumBorder(side: BorderSide(color: c.neutral300)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kMinTapTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: <Widget>[
                  Icon(
                    icon,
                    size: 15,
                    color: enabled ? c.accent700 : c.neutral400,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.titleSmall?.copyWith(
                        color: enabled ? c.text : c.neutral600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 5,
        decoration: BoxDecoration(
          color: context.colors.neutral300,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}
