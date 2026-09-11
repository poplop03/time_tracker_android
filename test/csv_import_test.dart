import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tally/domain/import.dart';
import 'package:tally/domain/models.dart';
import 'package:tally/features/sync/csv_export.dart';
import 'package:tally/features/sync/csv_import.dart';

const String _header =
    'activity,group,started_at,ended_at,minutes,note,calendar_event_id';

void main() {
  final DateTime now = DateTime(2026, 9, 11, 18);

  group('parseCsv', () {
    test('splits plain records', () {
      final List<CsvRecord> r = parseCsv('a,b\nc,d\n');
      expect(r.map((CsvRecord x) => x.fields), <List<String>>[
        <String>['a', 'b'],
        <String>['c', 'd'],
      ]);
    });

    test('keeps commas and doubled quotes inside quoted fields', () {
      final CsvRecord r = parseCsv('"Email, then code","Read ""Dune"""').single;
      expect(r.fields, <String>['Email, then code', 'Read "Dune"']);
    });

    test('keeps line breaks inside quotes and counts lines past them', () {
      final List<CsvRecord> r = parseCsv('h\n"first\nsecond"\nnext\n');
      expect(r[1].fields.single, 'first\nsecond');
      expect(r[1].line, 2);
      expect(r[2].line, 4);
    });

    test('handles CRLF, a byte-order mark, and blank lines', () {
      final List<CsvRecord> r = parseCsv('﻿a,b\r\n\r\nc,d\r\n');
      expect(r, hasLength(2));
      expect(r.first.fields, <String>['a', 'b']);
      expect(r.last.fields, <String>['c', 'd']);
      expect(r.last.line, 3);
    });

    test('keeps empty trailing fields', () {
      expect(parseCsv('a,,').single.fields, <String>['a', '', '']);
    });

    test('a file without a final newline still yields its last record', () {
      expect(parseCsv('a,b\nc,d').last.fields, <String>['c', 'd']);
    });

    test('an unclosed quote is a whole-file problem naming its line', () {
      expect(
        () => parseCsv('a\n"never closed\n'),
        throwsA(isA<CsvFormatProblem>().having(
            (CsvFormatProblem p) => p.message, 'message', contains('Line 2'))),
      );
    });
  });

  group('decodeCsvBytes', () {
    test('reads UTF-8, including accents and dashes', () {
      expect(decodeCsvBytes(utf8.encode('Café – réunion')), 'Café – réunion');
    });

    test('falls back to Latin-1 for files a Windows spreadsheet saved', () {
      expect(decodeCsvBytes(latin1.encode('Café')), 'Café');
    });
  });

  group('readImport', () {
    test('reads back what the export writes', () {
      final List<TrackedBlock> blocks = <TrackedBlock>[
        TrackedBlock(
          id: 1,
          activityId: 1,
          activityName: 'Email, then code',
          groupName: 'Work',
          colorSeed: 1,
          startedAt: DateTime(2026, 9, 7, 9, 0, 12, 345),
          endedAt: DateTime(2026, 9, 7, 10, 30),
          note: 'Wrote "the intro"\nand fixed CI',
          calendarEventId: '42',
          syncDirty: false,
        ),
        TrackedBlock(
          id: 2,
          activityId: 2,
          activityName: 'Reading',
          groupName: null,
          colorSeed: 2,
          startedAt: DateTime(2026, 9, 8, 20),
          endedAt: DateTime(2026, 9, 8, 21),
        ),
      ];

      final ParsedImport parsed =
          readImport(CsvExport.buildCsv(blocks), now: now);

      expect(parsed.problems, isEmpty);
      expect(parsed.rows, hasLength(2));
      final ImportRow first = parsed.rows.first;
      expect(first.activity, 'Email, then code');
      expect(first.group, 'Work');
      expect(first.start, DateTime(2026, 9, 7, 9, 0, 12)); // cut to seconds
      expect(first.end, DateTime(2026, 9, 7, 10, 30));
      expect(first.note, 'Wrote "the intro"\nand fixed CI');
      expect(first.alreadyOnCalendar, isTrue);

      final ImportRow second = parsed.rows.last;
      expect(second.group, kUngrouped); // the repository treats this as none
      expect(second.note, isNull);
      expect(second.alreadyOnCalendar, isFalse);
    });

    test('accepts hand-made headers in any case or spacing', () {
      final ParsedImport parsed = readImport(
        'Name,Start Time,End-Time,Notes\n'
        'Gym,2026-09-10 07:00,2026-09-10 08:15,Legs\n',
        now: now,
      );
      expect(parsed.problems, isEmpty);
      expect(parsed.rows.single.activity, 'Gym');
      expect(parsed.rows.single.end, DateTime(2026, 9, 10, 8, 15));
      expect(parsed.rows.single.note, 'Legs');
    });

    test('works out the end from minutes when there is no end column', () {
      final ParsedImport parsed = readImport(
        'activity,started_at,minutes\nRun,2026-09-10T06:30:00,45\n',
        now: now,
      );
      expect(parsed.rows.single.end, DateTime(2026, 9, 10, 7, 15));
    });

    test('moves times with a zone into local time', () {
      final ParsedImport parsed = readImport(
        'activity,started_at,ended_at\n'
        'Call,2026-09-10T09:00:00Z,2026-09-10T10:00:00Z\n',
        now: now,
      );
      expect(parsed.rows.single.start, DateTime.utc(2026, 9, 10, 9).toLocal());
    });

    test('a file without the needed columns is refused as a whole', () {
      expect(
        () => readImport('title,when\nx,y\n', now: now),
        throwsA(isA<CsvFormatProblem>().having((CsvFormatProblem p) => p.message,
            'message', allOf(contains('started_at'), contains('ended_at')))),
      );
    });

    test('an empty file is refused; a header alone just has no rows', () {
      expect(() => readImport('', now: now), throwsA(isA<CsvFormatProblem>()));
      final ParsedImport headerOnly = readImport('$_header\n', now: now);
      expect(headerOnly.rows, isEmpty);
      expect(headerOnly.problems, isEmpty);
    });

    test('bad rows are reported by line while good rows still come through',
        () {
      final String csv = <String>[
        _header,
        'Good,,2026-09-10T09:00:00,2026-09-10T10:00:00,60,,',
        ',,2026-09-10T11:00:00,2026-09-10T12:00:00,60,,',
        'Bad start,,yesterday,2026-09-10T12:00:00,60,,',
        'Backwards,,2026-09-10T12:00:00,2026-09-10T11:00:00,,,',
        'Future,,2026-09-11T17:00:00,2026-09-11T19:00:00,,,',
        'Running,,2026-09-11T17:00:00,,,,',
        '${'x' * 121},,2026-09-10T13:00:00,2026-09-10T14:00:00,60,,',
      ].join('\n');

      final ParsedImport parsed = readImport(csv, now: now);

      expect(parsed.rows.single.activity, 'Good');
      expect(
        parsed.problems.map((RowProblem p) => p.line),
        <int>[3, 4, 5, 6, 7, 8],
      );
      expect(parsed.problems[0].reason, contains('no activity'));
      expect(parsed.problems[1].reason, contains('yesterday'));
      expect(parsed.problems[2].reason, contains('end after it starts'));
      expect(parsed.problems[3].reason, contains('future'));
      expect(parsed.problems[4].reason, contains('no end time'));
      expect(parsed.problems[5].reason, contains('120'));
    });
  });
}
