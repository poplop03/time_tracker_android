import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/organic_theme.dart';
import '../../core/time/day.dart';
import '../../data/prefs/settings_store.dart';
import '../../domain/import.dart';
import '../../providers.dart';
import '../../services/background_sync.dart';
import '../shell/widgets.dart';
import 'csv_import.dart';

/// Picks a CSV file, shows what importing it would do, and imports only once
/// the user confirms.
class ImportCsvButton extends ConsumerStatefulWidget {
  const ImportCsvButton({super.key});

  @override
  ConsumerState<ImportCsvButton> createState() => _ImportCsvButtonState();
}

class _ImportCsvButtonState extends ConsumerState<ImportCsvButton> {
  bool _busy = false;

  // Android's picker filters by MIME type, and CSV files turn up labelled
  // many ways — as octet-stream from Drive, as Excel from Windows. A file that
  // is not really CSV is refused once it is read, with a reason.
  static final XTypeGroup _csvFiles = XTypeGroup(
    label: 'CSV',
    extensions: <String>['csv'],
    mimeTypes: <String>[
      'text/*',
      'application/csv',
      'application/vnd.ms-excel',
      'application/octet-stream',
    ],
  );

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final XFile? file =
          await openFile(acceptedTypeGroups: <XTypeGroup>[_csvFiles]);
      if (file == null) return; // picker dismissed
      if (await file.length() > kMaxImportBytes) {
        _toast('That file is too large to be a Tally export.');
        return;
      }

      final DateTime now = ref.read(clockProvider)();
      final ParsedImport parsed =
          readImport(decodeCsvBytes(await file.readAsBytes()), now: now);
      final ImportOutcome preview = await ref
          .read(trackingRepositoryProvider)
          .importBlocks(parsed.rows, dryRun: true);
      if (!mounted) return;

      final bool? confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (BuildContext _) => ImportPreviewSheet(
          fileName: file.name,
          preview: preview,
          problems: parsed.problems,
          now: now,
        ),
      );
      if (confirmed != true) return;

      final ImportOutcome done =
          await ref.read(trackingRepositoryProvider).importBlocks(parsed.rows);

      final Settings settings = ref.read(settingsProvider);
      if (done.added > 0 &&
          settings.isConnected &&
          settings.direction != SyncDirection.pull) {
        await BackgroundSync.pushNow();
      }
      _toast(done.added == 0
          ? 'Nothing new to import.'
          : 'Imported ${done.added} block${done.added == 1 ? '' : 's'}.');
    } on CsvFormatProblem catch (e) {
      _toast(e.message);
    } on Exception catch (e) {
      _toast('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _import,
        icon: const Icon(LucideIcons.arrowUp, size: 16),
        label: Text(_busy ? 'Importing…' : 'Import from CSV'),
      ),
    );
  }
}

/// What importing a file will do, shown before anything is written. Pops
/// `true` when the user chooses to import.
class ImportPreviewSheet extends StatelessWidget {
  const ImportPreviewSheet({
    super.key,
    required this.fileName,
    required this.preview,
    required this.problems,
    required this.now,
  });

  final String fileName;
  final ImportOutcome preview;
  final List<RowProblem> problems;
  final DateTime now;

  static const int _shownProblems = 3;

  @override
  Widget build(BuildContext context) {
    final OrganicColors c = context.colors;
    final int added = preview.added;
    final bool canImport = added > 0;

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
            Text(
              canImport
                  ? 'Import ${_count(added, 'block')}?'
                  : 'Nothing new to import',
              style: context.texts.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodySmall,
            ),
            const SizedBox(height: 18),
            OrganicCard(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _SummaryLine(
                    icon: LucideIcons.circleCheck,
                    color: c.sage600,
                    title: canImport
                        ? '${_count(added, 'new block')} to add'
                        : 'No new blocks in this file',
                    detail: canImport && preview.firstStart != null
                        ? 'From ${formatShortDate(preview.firstStart!, now)} '
                            'to ${formatShortDate(preview.lastEnd!, now)}'
                        : null,
                  ),
                  if (preview.duplicates > 0)
                    _SummaryLine(
                      icon: LucideIcons.copy,
                      color: c.neutral600,
                      title: '${preview.duplicates} already in Tally',
                      detail: 'Skipped — they match blocks you have.',
                    ),
                  if (preview.overlapping > 0)
                    _SummaryLine(
                      icon: LucideIcons.layers,
                      color: c.accent700,
                      title: '${_count(preview.overlapping, 'block')} '
                          'overlapping yours',
                      detail: 'Skipped, ${_lines(preview.overlapLines)}. '
                          'Import never trims or replaces what you have.',
                    ),
                  if (problems.isNotEmpty)
                    _SummaryLine(
                      icon: LucideIcons.circleAlert,
                      color: c.accent700,
                      title: '${_count(problems.length, 'row')} '
                          'could not be read',
                      detail: <String>[
                        for (final RowProblem p
                            in problems.take(_shownProblems))
                          'Line ${p.line}: ${p.reason}',
                        if (problems.length > _shownProblems)
                          'and ${problems.length - _shownProblems} more.',
                      ].join('\n'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Nothing already in Tally is changed or removed.',
              style: context.texts.bodySmall,
            ),
            const SizedBox(height: 20),
            if (canImport)
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Import'),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Close'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

  /// "line 12", "lines 4 and 9", "lines 4, 9, 12, 20, 31 and 3 more".
  static String _lines(List<int> lines) {
    const int shown = 5;
    if (lines.length == 1) return 'line ${lines.single}';
    final List<int> head = lines.take(shown).toList();
    if (lines.length <= shown) {
      return 'lines ${head.sublist(0, head.length - 1).join(', ')} '
          'and ${head.last}';
    }
    return 'lines ${head.join(', ')} and ${lines.length - shown} more';
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.icon,
    required this.color,
    required this.title,
    this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: context.texts.titleSmall),
                if (detail != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(detail!, style: context.texts.bodySmall),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
