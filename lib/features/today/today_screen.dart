import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/organic_theme.dart';
import '../../core/time/day.dart';
import '../../core/time/formatting.dart';
import '../../domain/models.dart';
import '../../domain/timeline.dart';
import '../../providers.dart';
import '../shell/widgets.dart';
import 'fill_in_sheet.dart';
import 'tracking_actions.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  final TextEditingController _name = TextEditingController();
  String? _pendingGroup;
  bool _staleDismissed = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = ref.watch(tickerProvider).value ?? DateTime.now();
    final bool use24h = ref.watch(settingsProvider).use24h;
    final TrackedBlock? running = ref.watch(runningBlockProvider).value;
    final List<TrackedBlock> blocks =
        ref.watch(todayBlocksProvider).value ?? const <TrackedBlock>[];

    final Duration total = blocks.fold(
        Duration.zero, (Duration sum, TrackedBlock b) => sum + b.durationAt(now));
    final List<TimelineRow> rows = buildTimeline(blocks);

    final bool stale = running != null &&
        now.difference(running.startedAt) > kStaleAfter &&
        !_staleDismissed;

    return ScreenScaffold(
      title: formatDuration(total),
      kicker: formatDateKicker(now),
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          sliver: SliverList.list(children: <Widget>[
            Text('tracked today', style: context.texts.bodyMedium),
            const SizedBox(height: 20),
            if (stale)
              _StaleTimerCard(
                block: running,
                onKeep: () => setState(() => _staleDismissed = true),
                onEnd: () async {
                  await ref.read(trackingActionsProvider).endAtLastActivity();
                  if (mounted) setState(() => _staleDismissed = false);
                },
              ),
            if (stale) const SizedBox(height: 16),
            if (running != null)
              _RunningCard(
                block: running,
                now: now,
                use24h: use24h,
                onStop: () => ref.read(trackingActionsProvider).stop(),
              )
            else
              _StartCard(
                controller: _name,
                selectedGroup: _pendingGroup,
                onGroup: (String? g) => setState(() => _pendingGroup = g),
                onStart: _start,
              ),
            const SizedBox(height: 26),
            SectionTitle(
              'Timeline',
              trailing: TextButton.icon(
                onPressed: () => FillInSheet.show(context),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Add a block you missed'),
              ),
            ),
          ]),
        ),
        if (rows.isEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            sliver: const SliverToBoxAdapter(
              child: EmptyNote(
                icon: LucideIcons.clock,
                title: 'Nothing tracked yet today',
                body: 'Start the timer above, or fill in a block you already '
                    'finished. Everything stays on this device until you '
                    'connect a calendar.',
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            sliver: SliverList.separated(
              itemCount: rows.length,
              separatorBuilder: (BuildContext _, int _) => const SizedBox(height: 10),
              itemBuilder: (BuildContext context, int i) {
                final TimelineRow row = rows[i];
                return switch (row) {
                  TimelineEntry(block: final TrackedBlock b) =>
                    _EntryRow(block: b, now: now, use24h: use24h),
                  TimelineGap(start: final DateTime s, end: final DateTime e) =>
                    _GapRow(start: s, end: e, use24h: use24h),
                };
              },
            ),
          ),
      ],
    );
  }

  Future<void> _start() async {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Name it first, then start.')));
      return;
    }
    await ref
        .read(trackingActionsProvider)
        .start(name, groupName: _pendingGroup);
    if (!mounted) return;
    _name.clear();
    setState(() {
      _pendingGroup = null;
      _staleDismissed = false;
    });
    FocusScope.of(context).unfocus();
  }
}

/// Accent-tinted card shown while the timer runs.
class _RunningCard extends StatelessWidget {
  const _RunningCard({
    required this.block,
    required this.now,
    required this.use24h,
    required this.onStop,
  });

  final TrackedBlock block;
  final DateTime now;
  final bool use24h;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    return OrganicCard(
      color: c.accent200,
      border: Border.all(color: c.accent400, width: 2),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const _PulsingDot(),
              const SizedBox(width: 8),
              Text(
                'Tracking now',
                style: context.texts.bodySmall?.copyWith(
                  color: c.accent800,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              GroupPill(
                block.group,
                color: c.accent800,
                background: Colors.white.withValues(alpha: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            block.activityName,
            style: context.texts.headlineMedium?.copyWith(color: c.accent900),
          ),
          const SizedBox(height: 6),
          SteadyDigits(
            formatStopwatch(block.durationAt(now)),
            style: context.texts.displayLarge!.copyWith(color: c.accent900),
          ),
          const SizedBox(height: 2),
          Text(
            'since ${formatClock(block.startedAt, use24h)}',
            style: context.texts.bodyMedium?.copyWith(color: c.accent800),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onStop,
              style: FilledButton.styleFrom(
                backgroundColor: c.accent900,
                foregroundColor: Colors.white,
                minimumSize: const Size(kMinTapTarget, 52),
                shape: OrganicRadii.pill,
              ),
              icon: const Icon(LucideIcons.square, size: 16),
              label: const Text('Stop'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: context.colors.accent700,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Idle state: name the activity, pick a group, then start.
class _StartCard extends ConsumerWidget {
  const _StartCard({
    required this.controller,
    required this.selectedGroup,
    required this.onGroup,
    required this.onStart,
  });

  final TextEditingController controller;
  final String? selectedGroup;
  final ValueChanged<String?> onGroup;
  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final OrganicColors c = context.colors;
    final List<String> groups =
        ref.watch(groupsProvider).value ?? const <String>[];

    return OrganicCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: controller,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => onStart(),
            decoration: const InputDecoration(hintText: 'What are you doing?'),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ChoiceChip(
                label: const Text('No group'),
                selected: selectedGroup == null,
                onSelected: (_) => onGroup(null),
              ),
              for (final String g in groups)
                ChoiceChip(
                  label: Text(g),
                  selected: selectedGroup == g,
                  onSelected: (_) => onGroup(g),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: Semantics(
              button: true,
              label: 'Start tracking',
              child: InkWell(
                onTap: onStart,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: c.accent700,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.play,
                      size: 30, color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text('Start', style: context.texts.titleSmall),
          ),
        ],
      ),
    );
  }
}

/// One tracked block in the timeline.
class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.block, required this.now, required this.use24h});

  final TrackedBlock block;
  final DateTime now;
  final bool use24h;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: OrganicRadii.row,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 62,
            child: Text(
              formatClock(block.startedAt, use24h),
              style: context.texts.bodySmall?.copyWith(color: c.neutral700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 5, right: 12),
            child: ActivityDot(block.colorSeed),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(block.activityName, style: context.texts.titleMedium),
                const SizedBox(height: 2),
                Text(
                  '${formatDuration(block.durationAt(now))}  ·  '
                  '${formatSpan(block.startedAt, block.endedAt, use24h)}',
                  style: context.texts.bodySmall,
                ),
                if (block.note != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    block.note!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
          if (block.isSynced)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Tooltip(
                message: 'On your calendar',
                child: Icon(LucideIcons.check, size: 16, color: c.sage600),
              ),
            ),
        ],
      ),
    );
  }
}

/// A dashed, tappable untracked stretch.
class _GapRow extends StatelessWidget {
  const _GapRow({required this.start, required this.end, required this.use24h});

  final DateTime start;
  final DateTime end;
  final bool use24h;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    final Duration gap = end.difference(start);
    return Semantics(
      button: true,
      label: 'Untracked ${formatDuration(gap)} from '
          '${formatClock(start, use24h)}. Fill it in.',
      child: InkWell(
        onTap: () => FillInSheet.show(context, start: start, end: end),
        borderRadius: OrganicRadii.row,
        child: CustomPaint(
          painter: _DashedBorderPainter(color: c.neutral400),
          child: Container(
            constraints: const BoxConstraints(minHeight: kMinTapTarget),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 62,
                  child: Text(
                    formatClock(start, use24h),
                    style: context.texts.bodySmall?.copyWith(color: c.neutral700),
                  ),
                ),
                const SizedBox(width: 22),
                Expanded(
                  child: Text(
                    '${formatDuration(gap)} untracked',
                    style: context.texts.bodySmall?.copyWith(color: c.neutral700),
                  ),
                ),
                Icon(LucideIcons.plus, size: 16, color: c.accent700),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final RRect rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(24),
    );
    final Path path = Path()..addRRect(rect);

    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double next = distance + 7;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + 6;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Shown when a timer has been running for more than half a day.
class _StaleTimerCard extends StatelessWidget {
  const _StaleTimerCard({
    required this.block,
    required this.onKeep,
    required this.onEnd,
  });

  final TrackedBlock block;
  final VoidCallback onKeep;
  final Future<void> Function() onEnd;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    return OrganicCard(
      color: c.sage100,
      border: Border.all(color: c.sage300),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Still tracking “${block.activityName}”?',
              style: context.texts.headlineSmall?.copyWith(color: c.sage800)),
          const SizedBox(height: 4),
          Text(
            'It has been running since '
            '${formatDateKicker(block.startedAt)}.',
            style: context.texts.bodyMedium?.copyWith(color: c.sage800),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: onKeep,
                  child: const Text('Keep going'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: onEnd,
                  child: const Text('End it'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
