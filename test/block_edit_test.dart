import 'package:flutter_test/flutter_test.dart';
import 'package:tally/domain/block_edit.dart';

void main() {
  final DateTime now = DateTime(2026, 9, 11, 18);

  group('blockTimesProblem', () {
    test('a sensible past block is fine', () {
      expect(
        blockTimesProblem(
          start: DateTime(2026, 9, 11, 9),
          end: DateTime(2026, 9, 11, 10),
          now: now,
        ),
        isNull,
      );
    });

    test('a block may cross midnight', () {
      expect(
        blockTimesProblem(
          start: DateTime(2026, 9, 10, 23),
          end: DateTime(2026, 9, 11, 1),
          now: now,
        ),
        isNull,
      );
    });

    test('ending before or at the start is refused', () {
      expect(
        blockTimesProblem(
          start: DateTime(2026, 9, 11, 10),
          end: DateTime(2026, 9, 11, 9),
          now: now,
        ),
        isNotNull,
      );
      expect(
        blockTimesProblem(
          start: DateTime(2026, 9, 11, 10),
          end: DateTime(2026, 9, 11, 10),
          now: now,
        ),
        isNotNull,
      );
    });

    test('a finished block cannot end in the future', () {
      expect(
        blockTimesProblem(
          start: DateTime(2026, 9, 11, 17),
          end: DateTime(2026, 9, 11, 19),
          now: now,
        ),
        contains('future'),
      );
    });
  });

  group('cleanNote', () {
    test('trims, and stores blank as absent', () {
      expect(cleanNote('  Wrote the intro  '), 'Wrote the intro');
      expect(cleanNote('   '), isNull);
      expect(cleanNote(''), isNull);
      expect(cleanNote(null), isNull);
    });

    test('keeps line breaks inside a description', () {
      expect(cleanNote('first\nsecond'), 'first\nsecond');
    });
  });
}
