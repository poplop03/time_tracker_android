import 'package:flutter_test/flutter_test.dart';
import 'package:tally/core/time/day.dart';

void main() {
  final DateTime now = DateTime(2026, 9, 11, 18);

  group('formatShortDate', () {
    test('leaves the year off within the current year', () {
      expect(formatShortDate(DateTime(2026, 9, 7, 9), now), 'Mon 7 Sep');
    });

    test('adds the year for another year', () {
      expect(formatShortDate(DateTime(2025, 12, 31), now), 'Wed 31 Dec 2025');
    });
  });

  group('formatDayLabel', () {
    test('names today and yesterday', () {
      expect(formatDayLabel(DateTime(2026, 9, 11, 1), now), 'Today');
      expect(formatDayLabel(DateTime(2026, 9, 10, 23), now), 'Yesterday');
    });

    test('finds yesterday across a month boundary', () {
      expect(
        formatDayLabel(DateTime(2026, 8, 31, 22), DateTime(2026, 9, 1, 8)),
        'Yesterday',
      );
    });

    test('spells out older days, with the year only when it differs', () {
      expect(formatDayLabel(DateTime(2026, 9, 7), now), 'Monday, 7 September');
      expect(
        formatDayLabel(DateTime(2025, 9, 7), now),
        'Sunday, 7 September 2025',
      );
    });
  });
}
