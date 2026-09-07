import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/organic_theme.dart';
import '../../core/time/day.dart';
import '../../core/time/formatting.dart';
import '../../domain/models.dart';
import '../../providers.dart';
import '../shell/widgets.dart';
import 'donut.dart';

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<DayTotal> week = ref.watch(weekTotalsProvider);
    final List<GroupSlice> slices = ref.watch(weekBreakdownProvider);
    final Duration weekTotal = week.fold(
        Duration.zero, (Duration sum, DayTotal d) => sum + d.total);

    return ScreenScaffold(
      title: formatDuration(weekTotal),
      kicker: 'Last 7 days',
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          sliver: SliverList.list(children: <Widget>[
            Text('tracked across the week', style: context.texts.bodyMedium),
            const SizedBox(height: 20),
            _WeekBars(days: week),
            const SizedBox(height: 24),
            const SectionTitle('By group'),
            if (slices.isEmpty)
              const EmptyNote(
                icon: LucideIcons.chartPie,
                title: 'No groups to show yet',
                body: 'Once you have tracked something this week, its groups '
                    'appear here with their share of the total.',
              )
            else
              _GroupBreakdown(slices: slices),
          ]),
        ),
      ],
    );
  }
}

/// Seven daily bars; today is the accent one.
class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.days});
  final List<DayTotal> days;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    final DateTime today = startOfDay(DateTime.now());
    final int maxSeconds = days.fold(
        1, (int m, DayTotal d) => d.total.inSeconds > m ? d.total.inSeconds : m);

    return OrganicCard(
      child: SizedBox(
        height: 170,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            for (final DayTotal day in days)
              Expanded(
                child: Semantics(
                  label: '${weekdayInitial(day.day)}: '
                      '${formatDuration(day.total)}',
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        day.total == Duration.zero
                            ? '—'
                            : formatDuration(day.total),
                        style: context.texts.bodySmall?.copyWith(
                          fontSize: 10,
                          color: isSameDay(day.day, today)
                              ? c.accent800
                              : c.neutral700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Container(
                          height: (110 * day.total.inSeconds / maxSeconds)
                              .clamp(4, 110)
                              .toDouble(),
                          decoration: BoxDecoration(
                            color: isSameDay(day.day, today)
                                ? c.accent
                                : c.neutral300,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        weekdayInitial(day.day),
                        style: context.texts.bodySmall?.copyWith(
                          color: isSameDay(day.day, today)
                              ? c.accent800
                              : c.neutral700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GroupBreakdown extends StatelessWidget {
  const _GroupBreakdown({required this.slices});
  final List<GroupSlice> slices;

  @override
  Widget build(BuildContext context) {
    final GroupSlice biggest = slices.first;
    return OrganicCard(
      child: Column(
        children: <Widget>[
          Center(child: GroupDonut(slices: slices)),
          const SizedBox(height: 20),
          for (final GroupSlice slice in slices) ...<Widget>[
            _LegendRow(slice: slice),
            if (slice != slices.last) const SizedBox(height: 14),
          ],
          const SizedBox(height: 18),
          Text(
            '${biggest.group} took the biggest share of your week — '
            '${biggest.percent}% of everything you tracked.',
            style: context.texts.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.slice});
  final GroupSlice slice;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            ActivityDot(slice.colorSeed),
            const SizedBox(width: 10),
            Expanded(child: Text(slice.group, style: context.texts.titleSmall)),
            Text(formatDuration(slice.total), style: context.texts.titleSmall),
            const SizedBox(width: 10),
            SizedBox(
              width: 40,
              child: Text(
                '${slice.percent}%',
                textAlign: TextAlign.right,
                style: context.texts.bodySmall?.copyWith(color: c.neutral700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ShareBar(
          fraction: slice.percent / 100,
          color: OrganicColors.dot(slice.colorSeed),
        ),
      ],
    );
  }
}
