import 'package:flutter_test/flutter_test.dart';
import 'package:tally/domain/models.dart';
import 'package:tally/features/sync/csv_export.dart';

TrackedBlock block({
  required String name,
  String? group,
  String? note,
  DateTime? end,
}) {
  final DateTime start = DateTime(2026, 9, 7, 9);
  return TrackedBlock(
    id: 1,
    activityId: 1,
    activityName: name,
    groupName: group,
    colorSeed: 1,
    startedAt: start,
    endedAt: end ?? start.add(const Duration(minutes: 90)),
    note: note,
  );
}

void main() {
  test('writes a header even with no rows', () {
    final String csv = CsvExport.buildCsv(const <TrackedBlock>[]);
    expect(csv.trim(),
        'activity,group,started_at,ended_at,minutes,note,calendar_event_id');
  });

  test('a running block is left out', () {
    final TrackedBlock running = TrackedBlock(
      id: 1,
      activityId: 1,
      activityName: 'Live',
      groupName: null,
      colorSeed: 1,
      startedAt: DateTime(2026, 9, 7, 9),
    );
    expect(CsvExport.buildCsv(<TrackedBlock>[running]).trim().split('\n'),
        hasLength(1));
  });

  test('quotes are escaped rather than breaking the row', () {
    final String csv = CsvExport.buildCsv(
        <TrackedBlock>[block(name: 'Read "Dune"', group: 'Life')]);
    expect(csv, contains('"Read ""Dune"""'));
    expect(csv.trim().split('\n'), hasLength(2));
  });

  test('commas inside a name stay in one cell', () {
    final String csv =
        CsvExport.buildCsv(<TrackedBlock>[block(name: 'Email, then code')]);
    final String row = csv.trim().split('\n')[1];
    expect(row, startsWith('"Email, then code"'));
    expect(row.split('","').first, '"Email, then code');
  });

  test('an ungrouped block reports the catch-all bucket', () {
    final String csv = CsvExport.buildCsv(<TrackedBlock>[block(name: 'Reading')]);
    expect(csv, contains('"$kUngrouped"'));
  });

  test('duration is written in whole minutes', () {
    final String csv = CsvExport.buildCsv(<TrackedBlock>[block(name: 'Code')]);
    expect(csv.trim().split('\n')[1], contains(',90,'));
  });
}
