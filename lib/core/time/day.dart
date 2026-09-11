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

const List<String> _shortWeekdays = <String>[
  'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
];

const List<String> _shortMonths = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Mon 7 Sep", with the year added only when it is not [now]'s year.
String formatShortDate(DateTime d, DateTime now) {
  final String base =
      '${_shortWeekdays[d.weekday - 1]} ${d.day} ${_shortMonths[d.month - 1]}';
  return d.year == now.year ? base : '$base ${d.year}';
}

/// "Today", "Yesterday", or the full date — for lists of past blocks.
/// Yesterday is found by calendar day, not by subtracting 24 hours, which
/// would skip a day across a daylight-saving change.
String formatDayLabel(DateTime d, DateTime now) {
  if (isSameDay(d, now)) return 'Today';
  if (isSameDay(d, DateTime(now.year, now.month, now.day - 1))) {
    return 'Yesterday';
  }
  final String full = formatDateKicker(d);
  return d.year == now.year ? full : '$full ${d.year}';
}
