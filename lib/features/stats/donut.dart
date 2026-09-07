import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/organic_theme.dart';
import '../../core/time/formatting.dart';
import '../../domain/models.dart';

/// Donut of group totals with the grand total in the hole. Sweep angles come
/// straight from the durations, so the ring always closes.
class GroupDonut extends StatelessWidget {
  const GroupDonut({super.key, required this.slices, this.size = 190});

  final List<GroupSlice> slices;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Duration total = slices.fold(
        Duration.zero, (Duration sum, GroupSlice s) => sum + s.total);
    final OrganicColors c = context.colors;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(slices: slices, trackColor: c.neutral300),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(formatDuration(total), style: context.texts.headlineMedium),
              const SizedBox(height: 2),
              Text('this week', style: context.texts.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.slices, required this.trackColor});

  final List<GroupSlice> slices;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double stroke = size.width * 0.16;
    final Rect rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    final Paint track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, track);

    final int totalSeconds =
        slices.fold(0, (int sum, GroupSlice s) => sum + s.total.inSeconds);
    if (totalSeconds == 0) return;

    const double gap = 0.02;
    double start = -math.pi / 2;
    for (final GroupSlice slice in slices) {
      final double sweep = (slice.total.inSeconds / totalSeconds) * math.pi * 2;
      if (sweep <= 0) continue;
      final Paint paint = Paint()
        ..color = OrganicColors.dot(slice.colorSeed)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;
      final double drawn = math.max(sweep - gap, 0.005);
      canvas.drawArc(rect, start + gap / 2, drawn, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.slices != slices || oldDelegate.trackColor != trackColor;
}
