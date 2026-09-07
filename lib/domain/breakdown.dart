import 'models.dart';

/// Totals per group, sorted longest first, with percents that sum to exactly
/// 100 (the largest slice absorbs the rounding remainder).
List<GroupSlice> groupBreakdown(
  List<ActivitySummary> activities,
  List<TrackedBlock> blocks, {
  DateTime? now,
}) {
  if (blocks.isEmpty) return const <GroupSlice>[];

  final Map<int, ActivitySummary> byId = <int, ActivitySummary>{
    for (final ActivitySummary a in activities) a.id: a,
  };

  final Map<String, Duration> totals = <String, Duration>{};
  final Map<String, int> seeds = <String, int>{};

  for (final TrackedBlock block in blocks) {
    final ActivitySummary? activity = byId[block.activityId];
    final String group = normalizeGroup(activity?.groupName ?? block.groupName);
    final Duration d =
        now != null ? block.durationAt(now) : block.duration;
    if (d <= Duration.zero) continue;
    totals[group] = (totals[group] ?? Duration.zero) + d;
    seeds[group] ??= activity?.colorSeed ?? block.colorSeed;
  }

  final int grandTotal =
      totals.values.fold(0, (int sum, Duration d) => sum + d.inSeconds);
  if (grandTotal == 0) return const <GroupSlice>[];

  final List<MapEntry<String, Duration>> entries = totals.entries.toList()
    ..sort((MapEntry<String, Duration> a, MapEntry<String, Duration> b) {
      final int byTotal = b.value.compareTo(a.value);
      return byTotal != 0 ? byTotal : a.key.compareTo(b.key);
    });

  final List<GroupSlice> slices = <GroupSlice>[];
  int assigned = 0;
  for (int i = 0; i < entries.length; i++) {
    final MapEntry<String, Duration> e = entries[i];
    final int percent = i == 0
        ? 0 // filled in below, after the remainder is known
        : (e.value.inSeconds * 100 / grandTotal).round();
    assigned += percent;
    slices.add(GroupSlice(
      group: e.key,
      total: e.value,
      percent: percent,
      colorSeed: seeds[e.key] ?? i,
    ));
  }

  // The biggest slice takes whatever is left so the column always reads 100 %.
  final GroupSlice first = slices.first;
  slices[0] = GroupSlice(
    group: first.group,
    total: first.total,
    percent: (100 - assigned).clamp(0, 100),
    colorSeed: first.colorSeed,
  );

  return slices;
}
