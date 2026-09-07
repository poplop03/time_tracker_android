import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/organic_theme.dart';
import '../../core/time/formatting.dart';
import '../../data/repositories/tracking_repository.dart';
import '../../providers.dart';
import '../shell/widgets.dart';

/// The "add a block you missed" sheet, also used to fill an untracked gap.
/// Times move in 15-minute steps and the duration updates as you go.
class FillInSheet extends ConsumerStatefulWidget {
  const FillInSheet({super.key, this.initialStart, this.initialEnd});

  final DateTime? initialStart;
  final DateTime? initialEnd;

  static Future<void> show(
    BuildContext context, {
    DateTime? start,
    DateTime? end,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext _) =>
          FillInSheet(initialStart: start, initialEnd: end),
    );
  }

  @override
  ConsumerState<FillInSheet> createState() => _FillInSheetState();
}

class _FillInSheetState extends ConsumerState<FillInSheet> {
  static const Duration _step = Duration(minutes: 15);

  final TextEditingController _name = TextEditingController();
  late DateTime _start;
  late DateTime _end;
  String? _group;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _end = widget.initialEnd ?? _roundTo15(now);
    _start = widget.initialStart ?? _end.subtract(const Duration(hours: 1));
    if (!_end.isAfter(_start)) _end = _start.add(_step);
  }

  static DateTime _roundTo15(DateTime t) {
    final int minutes = (t.minute ~/ 15) * 15;
    return DateTime(t.year, t.month, t.day, t.hour, minutes);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Duration get _duration => _end.difference(_start);

  void _nudge({required bool isStart, required int steps}) {
    setState(() {
      final Duration delta = _step * steps;
      if (isStart) {
        final DateTime next = _start.add(delta);
        if (!next.isBefore(_end)) return;
        _start = next;
      } else {
        final DateTime next = _end.add(delta);
        if (!next.isAfter(_start)) return;
        _end = next;
      }
    });
  }

  Future<void> _save() async {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      _toast('Give the block a name first.');
      return;
    }
    setState(() => _saving = true);
    try {
      final BlockPlacement result =
          await ref.read(trackingRepositoryProvider).addRetroactive(
                activityName: name,
                groupName: _group,
                start: _start,
                end: _end,
              );
      if (!mounted) return;
      Navigator.of(context).pop();
      if (result.trimmed > 0 || result.removed > 0) {
        _toast('Saved — ${result.trimmed} block(s) trimmed'
            '${result.removed > 0 ? ', ${result.removed} replaced' : ''}.');
      }
    } on OverlapRejected catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(e.message);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    final bool use24h = ref.watch(settingsProvider).use24h;
    final List<String> groups =
        ref.watch(groupsProvider).value ?? const <String>[];

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
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: c.neutral300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text('Fill in a block', style: context.texts.headlineMedium),
            const SizedBox(height: 4),
            Text(
              'Time you already spent, added after the fact.',
              style: context.texts.bodyMedium,
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'What was it?'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            _GroupChips(
              groups: groups,
              selected: _group,
              onSelected: (String? g) => setState(() => _group = g),
            ),
            const SizedBox(height: 18),
            _TimeStepper(
              label: 'Started',
              value: formatClock(_start, use24h),
              onMinus: () => _nudge(isStart: true, steps: -1),
              onPlus: () => _nudge(isStart: true, steps: 1),
            ),
            const SizedBox(height: 10),
            _TimeStepper(
              label: 'Ended',
              value: formatClock(_end, use24h),
              onMinus: () => _nudge(isStart: false, steps: -1),
              onPlus: () => _nudge(isStart: false, steps: 1),
            ),
            const SizedBox(height: 16),
            OrganicCard(
              color: c.accent200,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: <Widget>[
                  Icon(LucideIcons.hourglass, size: 18, color: c.accent800),
                  const SizedBox(width: 10),
                  Text('That is ', style: context.texts.bodyMedium?.copyWith(color: c.accent800)),
                  Text(
                    formatDuration(_duration),
                    style: context.texts.titleMedium?.copyWith(color: c.accent900),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save block'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeStepper extends StatelessWidget {
  const _TimeStepper({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return OrganicCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: context.texts.bodySmall),
                const SizedBox(height: 2),
                Text(value, style: context.texts.titleMedium),
              ],
            ),
          ),
          _StepButton(
            icon: LucideIcons.minus,
            onTap: onMinus,
            semanticLabel: '$label 15 minutes earlier',
          ),
          const SizedBox(width: 8),
          _StepButton(
            icon: LucideIcons.plus,
            onTap: onPlus,
            semanticLabel: '$label 15 minutes later',
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: kMinTapTarget,
          height: kMinTapTarget,
          decoration: BoxDecoration(
            color: c.neutral200,
            shape: BoxShape.circle,
            border: Border.all(color: c.neutral300),
          ),
          child: Icon(icon, size: 18, color: c.accent700),
        ),
      ),
    );
  }
}

/// Existing groups plus a "No group" escape hatch.
class _GroupChips extends StatelessWidget {
  const _GroupChips({
    required this.groups,
    required this.selected,
    required this.onSelected,
  });

  final List<String> groups;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        ChoiceChip(
          label: const Text('No group'),
          selected: selected == null,
          onSelected: (_) => onSelected(null),
        ),
        for (final String g in groups)
          ChoiceChip(
            label: Text(g),
            selected: selected == g,
            onSelected: (_) => onSelected(g),
          ),
      ],
    );
  }
}
