import 'package:intl/intl.dart';

import '../l10n/generated/app_localizations.dart';
import 'phnom_penh_time.dart';

// Date and time in K wording, always in Phnom Penh time and the UI language
// of the given l10n. Pass `now` from `clockProvider` so screens and tests
// agree.

/// "Thu 22 Oct".
String formatShortDate(AppLocalizations l10n, DateTime instant) =>
    DateFormat('EEE d MMM', l10n.localeName).format(toPhnomPenh(instant));

/// "Today, Thu 22 Oct", "Tomorrow, Fri 23 Oct", otherwise "Mon 26 Oct".
String formatDeliveryDay(
  AppLocalizations l10n,
  DateTime instant, {
  required DateTime now,
}) {
  final date = formatShortDate(l10n, instant);
  return switch (phnomPenhDaysBetween(now, instant)) {
    0 => l10n.dateRelativeDay(l10n.dateToday, date),
    1 => l10n.dateRelativeDay(l10n.dateTomorrow, date),
    _ => date,
  };
}

/// "8:00 PM".
String formatTime(AppLocalizations l10n, DateTime instant) =>
    DateFormat('h:mm a', l10n.localeName).format(toPhnomPenh(instant));

/// "by 8:00 PM".
String formatByTime(AppLocalizations l10n, DateTime instant) =>
    l10n.timeBy(formatTime(l10n, instant));
