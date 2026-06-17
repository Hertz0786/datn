/// Centralised date/time formatting helpers for chat messages, posts,
/// notifications, support threads, etc.
///
/// Rule of thumb:
///   * Same calendar day as "now"  ->  "HH:mm"  (e.g. "09:42")
///   * Yesterday or earlier this year  ->  "dd MMM HH:mm"  (e.g. "13 Jun 21:08")
///   * Different year  ->  "dd MMM yyyy HH:mm"  (e.g. "13 Jun 2025 21:08")
class DateTimeFormatter {
  DateTimeFormatter._();

  static const List<String> _monthAbbreviations = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Returns a short, human-friendly representation of [value].
  /// Falls back to an empty string when the value is null or invalid.
  static String format(DateTime? value, {DateTime? now}) {
    if (value == null) {
      return '';
    }

    final DateTime local = value.toLocal();
    final DateTime reference = now ?? DateTime.now();
    final DateTime today = _dateOnly(reference);
    final DateTime target = _dateOnly(local);

    final String time = _formatTime(local);
    final String month = _monthAbbreviations[local.month - 1];

    if (target == today) {
      return time;
    }

    if (local.year == reference.year) {
      return '${_two(local.day)} $month $time';
    }

    return '${_two(local.day)} $month ${local.year} $time';
  }

  /// Same as [format] but always returns the full date and time, regardless
  /// of how recent the value is. Useful for tooltips or detailed lists.
  static String formatFull(DateTime? value) {
    if (value == null) {
      return '';
    }

    final DateTime local = value.toLocal();
    final String time = _formatTime(local);
    final String month = _monthAbbreviations[local.month - 1];
    return '${_two(local.day)} $month ${local.year} $time';
  }

  /// Friendly "x ago" string used by notification lists and similar surfaces.
  /// Falls back to [format] once the value is older than a week.
  static String relative(DateTime? value, {DateTime? now}) {
    if (value == null) {
      return '';
    }

    final DateTime local = value.toLocal();
    final DateTime reference = now ?? DateTime.now();
    final Duration diff = reference.difference(local);

    if (diff.isNegative) {
      // Future timestamp (clock skew, etc.) - just show the exact value.
      return format(local, now: reference);
    }

    if (diff.inSeconds < 45) {
      return 'Just now';
    }
    if (diff.inMinutes < 1) {
      return '${diff.inSeconds}s ago';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    }
    if (diff.inHours < 24 && _dateOnly(local) == _dateOnly(reference)) {
      return '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }

    return format(local, now: reference);
  }

  static String _formatTime(DateTime value) {
    return '${_two(value.hour)}:${_two(value.minute)}';
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static String _two(int value) {
    return value.toString().padLeft(2, '0');
  }
}
