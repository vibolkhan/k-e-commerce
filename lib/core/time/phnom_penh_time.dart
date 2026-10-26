import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cambodia is UTC+7 all year (no daylight saving), so a fixed offset is
/// exact for Asia/Phnom_Penh.
const phnomPenhOffset = Duration(hours: 7);

typedef Clock = DateTime Function();

/// The current instant. Override in tests to freeze time.
final clockProvider = Provider<Clock>((ref) => DateTime.now);

/// [instant] as Phnom Penh wall-clock time, wherever the device is. The
/// result is a UTC [DateTime] whose fields (day, hour…) read as local
/// Cambodian time; use it for display and day comparisons only.
DateTime toPhnomPenh(DateTime instant) => instant.toUtc().add(phnomPenhOffset);

/// Now in Phnom Penh.
DateTime phnomPenhNow(Ref ref) => toPhnomPenh(ref.read(clockProvider)());

/// Whole calendar days from [from] to [to] in Phnom Penh: 0 same day,
/// 1 tomorrow, -1 yesterday.
int phnomPenhDaysBetween(DateTime from, DateTime to) {
  final a = toPhnomPenh(from);
  final b = toPhnomPenh(to);
  return DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
}
