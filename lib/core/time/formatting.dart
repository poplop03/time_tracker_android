// Pure formatting helpers. Kept free of Flutter imports so they can be
// unit-tested directly.

/// "1h 40m", "45m", "18h 05m" — minutes are zero-padded once hours are shown.
String formatDuration(Duration d) {
  final int totalMinutes = d.inMinutes;
  if (totalMinutes <= 0) return '0m';
  final int hours = totalMinutes ~/ 60;
  final int minutes = totalMinutes % 60;
  if (hours == 0) return '${minutes}m';
  return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
}

/// Compact variant used where space is tight: "1h 40m" -> "1h 40m", "0m" -> "—".
String formatDurationOrDash(Duration d) =>
    d.inMinutes <= 0 ? '—' : formatDuration(d);

/// "11:15am" in 12-hour mode, "11:15" in 24-hour mode.
String formatClock(DateTime t, bool use24h) {
  final String mm = t.minute.toString().padLeft(2, '0');
  if (use24h) return '${t.hour.toString().padLeft(2, '0')}:$mm';
  final String suffix = t.hour < 12 ? 'am' : 'pm';
  int hour = t.hour % 12;
  if (hour == 0) hour = 12;
  return '$hour:$mm$suffix';
}

/// Running-timer readout: "00:04:31".
String formatStopwatch(Duration d) {
  final int seconds = d.isNegative ? 0 : d.inSeconds;
  final String h = (seconds ~/ 3600).toString().padLeft(2, '0');
  final String m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
  final String s = (seconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

/// "9:15am – 10:40am" for a block's span.
String formatSpan(DateTime start, DateTime? end, bool use24h) {
  final String from = formatClock(start, use24h);
  if (end == null) return '$from – now';
  return '$from – ${formatClock(end, use24h)}';
}
