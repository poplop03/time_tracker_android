import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/models.dart';

/// Every finished block as CSV, handed to the system share sheet so the user
/// can put it wherever they keep things.
class CsvExport {
  const CsvExport();

  /// RFC 4180 quoting: wrap in quotes, double any quote inside.
  static String _cell(String value) =>
      '"${value.replaceAll('"', '""')}"';

  static String buildCsv(List<TrackedBlock> blocks) {
    final StringBuffer out = StringBuffer(
        'activity,group,started_at,ended_at,minutes,note,calendar_event_id\n');
    for (final TrackedBlock b in blocks) {
      if (b.endedAt == null) continue; // a running block has no duration yet
      out.writeln(<String>[
        _cell(b.activityName),
        _cell(b.group),
        _cell(b.startedAt.toIso8601String()),
        _cell(b.endedAt!.toIso8601String()),
        b.duration.inMinutes.toString(),
        _cell(b.note ?? ''),
        _cell(b.calendarEventId ?? ''),
      ].join(','));
    }
    return out.toString();
  }

  /// Writes the CSV to a temporary file and opens the share sheet. Returns the
  /// number of rows exported.
  Future<int> share(List<TrackedBlock> blocks) async {
    final String csv = buildCsv(blocks);
    final Directory dir = await getTemporaryDirectory();
    final String stamp = DateTime.now().toIso8601String().split('T').first;
    final File file = File('${dir.path}/tally-$stamp.csv');
    await file.writeAsString(csv);

    await SharePlus.instance.share(ShareParams(
      files: <XFile>[XFile(file.path, mimeType: 'text/csv')],
      subject: 'Tally export $stamp',
    ));
    return blocks.where((TrackedBlock b) => b.endedAt != null).length;
  }
}
