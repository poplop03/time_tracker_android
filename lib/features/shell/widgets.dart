import 'package:flutter/material.dart';

import '../../core/theme/organic_theme.dart';

/// The cream card every screen is built from.
class OrganicCard extends StatelessWidget {
  const OrganicCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.border,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? context.colors.surface,
        borderRadius: OrganicRadii.card,
        border: border,
      ),
      padding: padding,
      child: child,
    );
  }
}

/// A small pill used for group labels and metadata.
class GroupPill extends StatelessWidget {
  const GroupPill(this.label, {super.key, this.color, this.background});

  final String label;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background ?? c.neutral200,
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        border: Border.all(color: c.neutral300),
      ),
      child: Text(
        label,
        style: context.texts.bodySmall?.copyWith(color: color ?? c.neutral700),
      ),
    );
  }
}

/// The coloured dot that identifies an activity or a group.
class ActivityDot extends StatelessWidget {
  const ActivityDot(this.seed, {super.key, this.size = 10});
  final int seed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: OrganicColors.dot(seed),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Section heading used above lists.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(title, style: context.texts.headlineSmall)),
          ?trailing,
        ],
      ),
    );
  }
}

/// Honest empty state — never a fake zero.
class EmptyNote extends StatelessWidget {
  const EmptyNote({super.key, required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    return OrganicCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.neutral200,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: c.neutral700),
          ),
          const SizedBox(height: 14),
          Text(title, style: context.texts.headlineSmall),
          const SizedBox(height: 6),
          Text(body, style: context.texts.bodyMedium),
        ],
      ),
    );
  }
}

/// A horizontal share bar, used in the donut legend and the hour chart.
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.fraction, required this.color, this.height = 6});

  final double fraction;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.all(Radius.circular(height)),
      child: LinearProgressIndicator(
        value: fraction.clamp(0, 1),
        minHeight: height,
        backgroundColor: context.colors.neutral300,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

/// Screen scaffold with the Caprasimo title and a consistent gutter.
class ScreenScaffold extends StatelessWidget {
  const ScreenScaffold({
    super.key,
    required this.title,
    required this.kicker,
    required this.slivers,
  });

  final String title;
  final String kicker;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  kicker.toUpperCase(),
                  style: context.texts.bodySmall?.copyWith(
                    color: c.neutral700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(title, style: context.texts.displayMedium),
              ],
            ),
          ),
        ),
        ...slivers,
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}
