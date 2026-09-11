import 'package:flutter/foundation.dart';

/// A row from an import file that parsed into a finished block.
@immutable
class ImportRow {
  const ImportRow({
    required this.line,
    required this.activity,
    required this.start,
    required this.end,
    this.group,
    this.note,
    this.alreadyOnCalendar = false,
  });

  /// Line of the file the row starts on, for messages.
  final int line;
  final String activity;

  /// Raw group text; blank and "Ungrouped" both mean no group.
  final String? group;
  final DateTime start;
  final DateTime end;
  final String? note;

  /// The export recorded a calendar event for this block. The event id only
  /// means something on the phone that wrote it, so it is not kept — but the
  /// block is not pushed again either, which would duplicate the event.
  final bool alreadyOnCalendar;
}

/// What an import did — or, for a preview, would do.
@immutable
class ImportOutcome {
  const ImportOutcome({
    required this.added,
    required this.duplicates,
    required this.overlapLines,
    this.firstStart,
    this.lastEnd,
  });

  static const ImportOutcome none =
      ImportOutcome(added: 0, duplicates: 0, overlapLines: <int>[]);

  /// Blocks written, or that would be.
  final int added;

  /// Rows identical to a block Tally already has.
  final int duplicates;

  /// File lines of rows skipped because they overlap another block.
  final List<int> overlapLines;

  /// The span covered by the blocks added.
  final DateTime? firstStart;
  final DateTime? lastEnd;

  int get overlapping => overlapLines.length;
}
