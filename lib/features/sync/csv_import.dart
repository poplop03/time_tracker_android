import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/block_edit.dart';
import '../../domain/import.dart';

/// Reading a CSV file back into blocks — the counterpart of `CsvExport`.
///
/// This file only turns text into [ImportRow]s and reports the rows it could
/// not read. Deciding which rows fit around the blocks already stored is the
/// repository's job, so nothing here touches the database.

/// Files larger than this are refused rather than read into memory. Years of
/// tracking export to well under a megabyte.
const int kMaxImportBytes = 20 * 1024 * 1024;

/// The file as a whole cannot be imported.
class CsvFormatProblem implements Exception {
  CsvFormatProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One CSV record and the line of the file it starts on.
@immutable
class CsvRecord {
  const CsvRecord(this.line, this.fields);
  final int line;
  final List<String> fields;
}

/// A row that could not be read, and why.
@immutable
class RowProblem {
  const RowProblem(this.line, this.reason);
  final int line;
  final String reason;
}

@immutable
class ParsedImport {
  const ParsedImport({required this.rows, required this.problems});
  final List<ImportRow> rows;
  final List<RowProblem> problems;
}

/// File bytes as text: UTF-8 when valid, otherwise Latin-1, which is how
/// spreadsheets on Windows often save CSV.
String decodeCsvBytes(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// Splits RFC 4180 CSV into records. Handles quoted fields holding commas,
/// doubled quotes and line breaks (descriptions can span lines), CRLF endings,
/// a leading byte-order mark, and blank lines.
List<CsvRecord> parseCsv(String input) {
  final String text = input.startsWith('﻿') ? input.substring(1) : input;
  final List<CsvRecord> records = <CsvRecord>[];
  List<String> fields = <String>[];
  final StringBuffer field = StringBuffer();
  bool inQuotes = false;
  bool fieldStarted = false;
  int line = 1;
  int recordLine = 1;
  int quoteLine = 1;

  void endField() {
    fields.add(field.toString());
    field.clear();
    fieldStarted = false;
  }

  void endRecord() {
    endField();
    final bool blank = fields.length == 1 && fields.first.trim().isEmpty;
    if (!blank) records.add(CsvRecord(recordLine, List<String>.unmodifiable(fields)));
    fields = <String>[];
  }

  for (int i = 0; i < text.length; i++) {
    final String ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        if (ch == '\n') line++;
        field.write(ch);
      }
      continue;
    }

    switch (ch) {
      case '"':
        if (fieldStarted) {
          field.write(ch); // a stray quote mid-value is just a character
        } else {
          inQuotes = true;
          fieldStarted = true;
          quoteLine = line;
        }
      case ',':
        endField();
      case '\r':
        // CRLF is handled by the \n; a lone CR still ends the record.
        if (i + 1 < text.length && text[i + 1] == '\n') continue;
        endRecord();
        line++;
        recordLine = line;
      case '\n':
        endRecord();
        line++;
        recordLine = line;
      default:
        field.write(ch);
        fieldStarted = true;
    }
  }

  if (inQuotes) {
    throw CsvFormatProblem('Line $quoteLine opens a quoted value that never '
        'closes, so the file may be cut off.');
  }
  if (fieldStarted || fields.isNotEmpty) endRecord();
  return records;
}

/// Column names the importer understands. The first of each is what Tally's
/// own export writes; the others let a hand-made spreadsheet work too.
const Map<String, List<String>> _columnNames = <String, List<String>>{
  'activity': <String>['activity', 'name', 'title'],
  'group': <String>['group'],
  'started_at': <String>['started_at', 'start', 'started', 'start_time'],
  'ended_at': <String>['ended_at', 'end', 'ended', 'end_time'],
  'minutes': <String>['minutes', 'duration_minutes'],
  'note': <String>['note', 'notes', 'description'],
  'calendar_event_id': <String>['calendar_event_id'],
};

/// Longest activity name the database accepts.
const int _maxActivityLength = 120;

/// Reads a whole file. Throws [CsvFormatProblem] when the file cannot be used
/// at all; individual bad rows are returned as [ParsedImport.problems] so the
/// good ones still come through.
ParsedImport readImport(String csv, {required DateTime now}) {
  final List<CsvRecord> records = parseCsv(csv);
  if (records.isEmpty) throw CsvFormatProblem('That file is empty.');

  final List<String> header = records.first.fields
      .map((String f) =>
          f.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_'))
      .toList();
  final Map<String, int> column = <String, int>{};
  _columnNames.forEach((String key, List<String> names) {
    for (final String name in names) {
      final int i = header.indexOf(name);
      if (i >= 0) {
        column[key] = i;
        break;
      }
    }
  });

  final List<String> missing = <String>[
    if (!column.containsKey('activity')) 'activity',
    if (!column.containsKey('started_at')) 'started_at',
    if (!column.containsKey('ended_at') && !column.containsKey('minutes'))
      'ended_at',
  ];
  if (missing.isNotEmpty) {
    throw CsvFormatProblem(
        'This does not look like a Tally export: there is no '
        '${missing.join(' or ')} column. The first row needs column names '
        'such as activity, group, started_at, ended_at and note.');
  }

  String cell(CsvRecord record, String key) {
    final int? i = column[key];
    if (i == null || i >= record.fields.length) return '';
    return record.fields[i].trim();
  }

  final List<ImportRow> rows = <ImportRow>[];
  final List<RowProblem> problems = <RowProblem>[];

  for (final CsvRecord record in records.skip(1)) {
    void reject(String reason) => problems.add(RowProblem(record.line, reason));

    final String activity = cell(record, 'activity');
    if (activity.isEmpty) {
      reject('It has no activity name.');
      continue;
    }
    if (activity.length > _maxActivityLength) {
      reject('The activity name is longer than $_maxActivityLength characters.');
      continue;
    }

    final String startText = cell(record, 'started_at');
    final DateTime? start = _parseTime(startText);
    if (start == null) {
      reject(startText.isEmpty
          ? 'It has no start time.'
          : 'The start time “$startText” is not a date.');
      continue;
    }

    DateTime? end;
    final String endText = cell(record, 'ended_at');
    if (endText.isNotEmpty) {
      end = _parseTime(endText);
      if (end == null) {
        reject('The end time “$endText” is not a date.');
        continue;
      }
    } else {
      final int? minutes = int.tryParse(cell(record, 'minutes'));
      if (minutes != null && minutes > 0) {
        end = start.add(Duration(minutes: minutes));
      }
    }
    if (end == null) {
      reject('It has no end time.');
      continue;
    }

    final String? timesProblem =
        blockTimesProblem(start: start, end: end, now: now);
    if (timesProblem != null) {
      reject(timesProblem);
      continue;
    }

    final String group = cell(record, 'group');
    rows.add(ImportRow(
      line: record.line,
      activity: activity,
      group: group.isEmpty ? null : group,
      start: start,
      end: end,
      note: cleanNote(cell(record, 'note')),
      alreadyOnCalendar: cell(record, 'calendar_event_id').isNotEmpty,
    ));
  }

  return ParsedImport(rows: rows, problems: problems);
}

/// ISO 8601, with or without a zone. Times carrying a zone are moved to the
/// phone's local time; everything is cut to whole seconds, which is what the
/// database keeps, so re-importing an export matches what is already stored.
DateTime? _parseTime(String text) {
  if (text.isEmpty) return null;
  final DateTime? parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  final DateTime local = parsed.isUtc ? parsed.toLocal() : parsed;
  return DateTime(local.year, local.month, local.day, local.hour, local.minute,
      local.second);
}
