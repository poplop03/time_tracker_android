import 'package:flutter_test/flutter_test.dart';
import 'package:tally/core/time/formatting.dart';

void main() {
  group('formatDuration', () {
    test('minutes only, unpadded', () {
      expect(formatDuration(const Duration(minutes: 45)), '45m');
      expect(formatDuration(const Duration(minutes: 5)), '5m');
    });

    test('pads minutes once hours are shown', () {
      expect(formatDuration(const Duration(hours: 1, minutes: 40)), '1h 40m');
      expect(formatDuration(const Duration(hours: 18, minutes: 5)), '18h 05m');
      expect(formatDuration(const Duration(hours: 2)), '2h 00m');
    });

    test('drops seconds and never goes negative', () {
      expect(formatDuration(const Duration(minutes: 45, seconds: 59)), '45m');
      expect(formatDuration(Duration.zero), '0m');
      expect(formatDuration(const Duration(minutes: -10)), '0m');
    });
  });

  group('formatClock', () {
    test('12-hour', () {
      expect(formatClock(DateTime(2026, 9, 7, 11, 15), false), '11:15am');
      expect(formatClock(DateTime(2026, 9, 7, 13, 5), false), '1:05pm');
      expect(formatClock(DateTime(2026, 9, 7, 0, 30), false), '12:30am');
      expect(formatClock(DateTime(2026, 9, 7, 12, 0), false), '12:00pm');
    });

    test('24-hour', () {
      expect(formatClock(DateTime(2026, 9, 7, 11, 15), true), '11:15');
      expect(formatClock(DateTime(2026, 9, 7, 9, 5), true), '09:05');
      expect(formatClock(DateTime(2026, 9, 7, 0, 30), true), '00:30');
    });
  });

  group('formatStopwatch', () {
    test('always HH:MM:SS', () {
      expect(formatStopwatch(const Duration(seconds: 5)), '00:00:05');
      expect(
          formatStopwatch(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '01:02:03');
      expect(formatStopwatch(const Duration(seconds: -5)), '00:00:00');
    });
  });
}
