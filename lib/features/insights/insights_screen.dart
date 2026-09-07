import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/organic_theme.dart';
import '../../core/time/day.dart';
import '../../core/time/formatting.dart';
import '../../domain/models.dart';
import '../../providers.dart';
import '../shell/widgets.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final InsightSet insights = ref.watch(insightsProvider);
    final OrganicColors c = context.colors;

    return ScreenScaffold(
      title: 'Insights',
      kicker: insights.daysWithData == 0
          ? 'Last 30 days'
          : 'From ${insights.daysWithData} tracked day'
              '${insights.daysWithData == 1 ? '' : 's'}',
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          sliver: SliverList.list(children: <Widget>[
            if (insights.daysWithData == 0)
              const EmptyNote(
                icon: LucideIcons.lightbulb,
                title: 'Nothing to read yet',
                body: 'Track a couple of days and this page will tell you '
                    'where the time actually goes.',
              )
            else ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _StatTile(
                      icon: LucideIcons.hourglass,
                      label: 'Average tracked day',
                      value: formatDuration(insights.averageTrackedDay),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatTile(
                      icon: LucideIcons.zap,
                      label: 'Longest stretch',
                      value: formatDuration(insights.longestStretch),
                      caption: insights.longestStretchDay == null
                          ? null
                          : formatDateKicker(insights.longestStretchDay!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _UntrackedCard(share: insights.untrackedShare),
              const SizedBox(height: 24),
              const SectionTitle('When you do the work'),
              _HourBars(byHour: insights.byHour),
              const SizedBox(height: 20),
              OrganicCard(
                color: c.sage100,
                border: Border.all(color: c.sage300),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(LucideIcons.sparkles, size: 18, color: c.sage800),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        insights.observation,
                        style: context.texts.bodyLarge?.copyWith(color: c.sage800),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ]),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    return OrganicCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: c.accent700),
          const SizedBox(height: 12),
          Text(value, style: context.texts.headlineMedium),
          const SizedBox(height: 4),
          Text(label, style: context.texts.bodySmall),
          if (caption != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(caption!,
                style: context.texts.bodySmall?.copyWith(color: c.neutral600)),
          ],
        ],
      ),
    );
  }
}

class _UntrackedCard extends StatelessWidget {
  const _UntrackedCard({required this.share});
  final int share;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    return OrganicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text('Untracked share of waking hours',
                    style: context.texts.titleSmall),
              ),
              Text('$share%', style: context.texts.headlineSmall),
            ],
          ),
          const SizedBox(height: 10),
          ShareBar(fraction: share / 100, color: c.neutral600, height: 8),
          const SizedBox(height: 8),
          Text(
            'Measured against a 16-hour waking day on the days you tracked '
            'anything.',
            style: context.texts.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Deep-work-by-hour bars across the full 24 hours.
class _HourBars extends StatelessWidget {
  const _HourBars({required this.byHour});
  final List<Duration> byHour;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    final int maxSeconds = byHour.fold(
        1, (int m, Duration d) => d.inSeconds > m ? d.inSeconds : m);

    return OrganicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (int hour = 0; hour < 24; hour++)
                  Expanded(
                    child: Semantics(
                      label: '${formatClock(DateTime(2000, 1, 1, hour), false)}: '
                          '${formatDuration(byHour[hour])}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: Container(
                          height: (94 * byHour[hour].inSeconds / maxSeconds)
                              .clamp(3, 94)
                              .toDouble(),
                          decoration: BoxDecoration(
                            color: byHour[hour] == Duration.zero
                                ? c.neutral300
                                : c.sage500,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('12am', style: context.texts.bodySmall),
              Text('6am', style: context.texts.bodySmall),
              Text('12pm', style: context.texts.bodySmall),
              Text('6pm', style: context.texts.bodySmall),
              Text('11pm', style: context.texts.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}
