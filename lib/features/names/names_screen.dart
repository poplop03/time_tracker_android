import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/organic_theme.dart';
import '../../core/time/formatting.dart';
import '../../domain/models.dart';
import '../../providers.dart';
import '../shell/widgets.dart';
import 'block_editor.dart';

class NamesScreen extends ConsumerStatefulWidget {
  const NamesScreen({super.key});

  @override
  ConsumerState<NamesScreen> createState() => _NamesScreenState();
}

class _NamesScreenState extends ConsumerState<NamesScreen> {
  final TextEditingController _newName = TextEditingController();
  bool _selectMode = false;
  final Set<int> _selected = <int>{};

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<ActivitySummary> activities =
        ref.watch(activitiesProvider).value ?? const <ActivitySummary>[];

    // Ungrouped always sits last; other groups keep alphabetical order.
    final Map<String, List<ActivitySummary>> sections =
        <String, List<ActivitySummary>>{};
    for (final ActivitySummary a in activities) {
      sections.putIfAbsent(a.group, () => <ActivitySummary>[]).add(a);
    }
    final List<String> order = sections.keys.toList()
      ..sort((String a, String b) {
        if (a == kUngrouped) return 1;
        if (b == kUngrouped) return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    final Widget list = ScreenScaffold(
      title: 'Names',
      kicker: '${activities.length} activit'
          '${activities.length == 1 ? 'y' : 'ies'}',
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          sliver: SliverList.list(children: <Widget>[
            _AddActivityField(
              controller: _newName,
              onSubmit: _addActivity,
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _selectMode
                        ? 'Tap names to group them'
                        : 'Hold a name to edit its time blocks',
                    style: context.texts.bodyMedium,
                  ),
                ),
                if (activities.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _selectMode = !_selectMode;
                      _selected.clear();
                    }),
                    icon: Icon(
                      _selectMode ? LucideIcons.x : LucideIcons.folder,
                      size: 16,
                    ),
                    label: Text(_selectMode ? 'Cancel' : 'Group'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (activities.isEmpty)
              const EmptyNote(
                icon: LucideIcons.tag,
                title: 'No activity names yet',
                body: 'Names appear here the moment you track something, or '
                    'add one above to have it ready.',
              ),
          ]),
        ),
        for (final String group in order)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            sliver: SliverList.list(children: <Widget>[
              _GroupHeader(
                group: group,
                activities: sections[group]!,
                onUngroup: group == kUngrouped
                    ? null
                    : () => ref
                        .read(activityRepositoryProvider)
                        .ungroup(group),
              ),
              const SizedBox(height: 8),
              for (final ActivitySummary a in sections[group]!) ...<Widget>[
                _ActivityRow(
                  activity: a,
                  selectMode: _selectMode,
                  selected: _selected.contains(a.id),
                  onTap: () {
                    if (!_selectMode) return;
                    setState(() {
                      if (!_selected.remove(a.id)) _selected.add(a.id);
                    });
                  },
                  onLongPress: () => ActivityBlocksSheet.show(context, a),
                ),
                const SizedBox(height: 8),
              ],
            ]),
          ),
        SliverToBoxAdapter(
          child: SizedBox(height: _selectMode && _selected.isNotEmpty ? 90 : 0),
        ),
      ],
    );

    // The group action floats over the list while names are being picked.
    return Stack(
      children: <Widget>[
        list,
        if (_selectMode && _selected.isNotEmpty)
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: FilledButton(
              onPressed: _openGroupSheet,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
              child: Text('Group ${_selected.length} name'
                  '${_selected.length == 1 ? '' : 's'}'),
            ),
          ),
      ],
    );
  }

  Future<void> _addActivity() async {
    final String name = _newName.text.trim();
    if (name.isEmpty) return;
    await ref.read(activityRepositoryProvider).addActivity(name);
    if (!mounted) return;
    _newName.clear();
    FocusScope.of(context).unfocus();
  }

  Future<void> _openGroupSheet() async {
    final List<int> ids = _selected.toList();
    final String? group = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext _) => _GroupSheet(count: ids.length),
    );
    if (group == null) return;
    await ref.read(activityRepositoryProvider).assignGroup(
          ids,
          group == kUngrouped ? null : group,
        );
    if (!mounted) return;
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }
}

class _AddActivityField extends StatelessWidget {
  const _AddActivityField({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => onSubmit(),
            decoration: const InputDecoration(hintText: 'Add an activity name'),
          ),
        ),
        const SizedBox(width: 10),
        Semantics(
          button: true,
          label: 'Add activity',
          child: InkWell(
            onTap: onSubmit,
            customBorder: const CircleBorder(),
            child: Container(
              width: kMinTapTarget + 4,
              height: kMinTapTarget + 4,
              decoration: BoxDecoration(
                color: context.colors.accent700,
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.plus, size: 20, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.activities,
    required this.onUngroup,
  });

  final String group;
  final List<ActivitySummary> activities;
  final VoidCallback? onUngroup;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    final Duration total = activities.fold(
        Duration.zero, (Duration sum, ActivitySummary a) => sum + a.total);

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(group, style: context.texts.headlineSmall),
              const SizedBox(height: 2),
              Text(
                '${formatDurationOrDash(total)}  ·  ${activities.length} name'
                '${activities.length == 1 ? '' : 's'}',
                style: context.texts.bodySmall,
              ),
            ],
          ),
        ),
        if (onUngroup != null)
          Semantics(
            button: true,
            label: 'Ungroup $group',
            child: InkWell(
              onTap: onUngroup,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: kMinTapTarget,
                  minWidth: kMinTapTarget,
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: c.neutral400),
                ),
                child: Text(
                  'Ungroup',
                  style: context.texts.bodySmall?.copyWith(color: c.accent700),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.activity,
    required this.selectMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final ActivitySummary activity;
  final bool selectMode;
  final bool selected;
  final VoidCallback onTap;

  /// Opens the name's time blocks. Off while picking names to group, where a
  /// hold would be too easy to trigger by accident.
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    return Semantics(
      onLongPressHint: selectMode ? null : 'edit time blocks',
      child: InkWell(
      onTap: selectMode ? onTap : null,
      onLongPress: selectMode ? null : onLongPress,
      borderRadius: OrganicRadii.row,
      child: Container(
        constraints: const BoxConstraints(minHeight: kMinTapTarget),
        decoration: BoxDecoration(
          color: selected ? c.accent200 : c.surface,
          borderRadius: OrganicRadii.row,
          border: Border.all(
            color: selected ? c.accent400 : Colors.transparent,
            width: 2,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            if (selectMode)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  selected ? LucideIcons.circleDot : LucideIcons.circle,
                  size: 18,
                  color: selected ? c.accent700 : c.neutral400,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ActivityDot(activity.colorSeed),
              ),
            Expanded(
              child: Text(activity.name, style: context.texts.titleMedium),
            ),
            Text(
              '${formatDurationOrDash(activity.total)}  ·  '
              '${activity.blockCount}',
              style: context.texts.bodySmall,
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Type a new group name, or pick one that already exists.
class _GroupSheet extends ConsumerStatefulWidget {
  const _GroupSheet({required this.count});
  final int count;

  @override
  ConsumerState<_GroupSheet> createState() => _GroupSheetState();
}

class _GroupSheetState extends ConsumerState<_GroupSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    final List<String> groups =
        ref.watch(groupsProvider).value ?? const <String>[];

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
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
          Text('Group ${widget.count} name${widget.count == 1 ? '' : 's'}',
              style: context.texts.headlineMedium),
          const SizedBox(height: 4),
          Text('Call the group whatever makes sense to you.',
              style: context.texts.bodyMedium),
          const SizedBox(height: 18),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'New group name'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (String v) => _save(v),
          ),
          if (groups.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Text('or an existing group', style: context.texts.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String g in groups)
                  ActionChip(
                    label: Text(g),
                    onPressed: () => _save(g),
                  ),
                ActionChip(
                  label: const Text(kUngrouped),
                  onPressed: () => _save(kUngrouped),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _controller.text.trim().isEmpty
                  ? null
                  : () => _save(_controller.text),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }

  void _save(String value) {
    final String name = value.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }
}
