/// Why a finished block cannot take these times, or null when it can. Shared by
/// the edit sheet, which shows the reason inline, and the repository, which
/// refuses the write — so the two can never disagree.
String? blockTimesProblem({
  required DateTime start,
  required DateTime end,
  required DateTime now,
}) {
  if (!end.isAfter(start)) return 'A block has to end after it starts.';
  if (end.isAfter(now)) return 'A finished block cannot end in the future.';
  return null;
}

/// A description as stored: trimmed, and absent rather than blank.
String? cleanNote(String? raw) {
  final String value = (raw ?? '').trim();
  return value.isEmpty ? null : value;
}
