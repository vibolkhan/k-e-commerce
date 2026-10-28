import 'phnom_penh_time.dart';

/// Same-day delivery cut-off (market rule: 3:00 PM Phnom Penh). Orders placed
/// after it deliver the next day; the server decides, this is for display.
class Cutoff {
  const Cutoff(this.hour, this.minute);

  static const standard = Cutoff(15, 0);

  /// "15:00" from `app_settings.same_day_cutoff`; [standard] if unreadable.
  factory Cutoff.parse(String? value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value ?? '');
    if (match == null) return standard;
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    if (hour > 23 || minute > 59) return standard;
    return Cutoff(hour, minute);
  }

  final int hour;
  final int minute;

  /// Time left today in Phnom Penh, or null once the cut-off has passed.
  Duration? remaining(DateTime now) {
    final local = toPhnomPenh(now);
    final cutoff = DateTime.utc(
      local.year,
      local.month,
      local.day,
      hour,
      minute,
    );
    final left = cutoff.difference(local);
    return left > Duration.zero ? left : null;
  }
}
