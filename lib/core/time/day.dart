/// Local-day boundary helpers. Blocks are stored in UTC and displayed local,
/// so every range query is built from these.
DateTime startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

DateTime endOfDay(DateTime t) => startOfDay(t).add(const Duration(days: 1));

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// The last [days] local days, oldest first, each as a start-of-day instant.
List<DateTime> lastDays(DateTime now, int days) {
  final DateTime today = startOfDay(now);
  return List<DateTime>.generate(
    days,
    (int i) => today.subtract(Duration(days: days - 1 - i)),
  );
}

const List<String> kWeekdayInitials = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];

String weekdayInitial(DateTime d) => kWeekdayInitials[d.weekday - 1];

const List<String> _months = <String>[
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const List<String> _weekdays = <String>[
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

/// "Monday, 7 September" — the Today header kicker.
String formatDateKicker(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
