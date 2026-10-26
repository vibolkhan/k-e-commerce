import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:k_e_commerce/core/l10n/generated/app_localizations.dart';
import 'package:k_e_commerce/core/time/date_format.dart';
import 'package:k_e_commerce/core/time/phnom_penh_time.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final km = lookupAppLocalizations(const Locale('km'));

  // 10:00 on Thu 22 Oct 2026 in Phnom Penh.
  final now = DateTime.utc(2026, 10, 22, 3);

  setUpAll(initializeDateFormatting);

  group('toPhnomPenh', () {
    test('is UTC+7 whatever the input zone', () {
      final pp = toPhnomPenh(DateTime.utc(2026, 10, 22, 17));
      expect([pp.day, pp.hour], [23, 0]);
      final local = DateTime.utc(2026, 10, 22, 17).toLocal();
      expect(toPhnomPenh(local), pp);
    });

    test('days between compares Phnom Penh calendar days', () {
      // 23:30 Thu → 00:00 Fri is the next day there, though only 30 min.
      expect(
        phnomPenhDaysBetween(
          DateTime.utc(2026, 10, 22, 16, 30),
          DateTime.utc(2026, 10, 22, 17),
        ),
        1,
      );
      // 08:00 and 22:00 UTC on the 22nd are different days in Phnom Penh.
      expect(
        phnomPenhDaysBetween(
          DateTime.utc(2026, 10, 22, 8),
          DateTime.utc(2026, 10, 22, 22),
        ),
        1,
      );
    });
  });

  group('formatDeliveryDay', () {
    test('today', () {
      expect(
        formatDeliveryDay(en, DateTime.utc(2026, 10, 22, 13), now: now),
        'Today, Thu 22 Oct',
      );
    });

    test('tomorrow', () {
      expect(
        formatDeliveryDay(en, DateTime.utc(2026, 10, 23, 5), now: now),
        'Tomorrow, Fri 23 Oct',
      );
    });

    test('later dates have no relative word', () {
      expect(
        formatDeliveryDay(en, DateTime.utc(2026, 10, 26, 5), now: now),
        'Mon 26 Oct',
      );
    });

    test('just after midnight in Phnom Penh is already tomorrow', () {
      final lateThursday = DateTime.utc(2026, 10, 22, 16, 30); // 23:30
      expect(
        formatDeliveryDay(
          en,
          DateTime.utc(2026, 10, 22, 17),
          now: lateThursday,
        ),
        'Tomorrow, Fri 23 Oct',
      );
    });

    test('Khmer', () {
      final text = formatDeliveryDay(
        km,
        DateTime.utc(2026, 10, 22, 13),
        now: now,
      );
      expect(text, startsWith('ថ្ងៃនេះ '));
      expect(text, contains('22'));
      expect(text, isNot(contains('Thu')));
    });
  });

  group('time', () {
    // 20:00 in Phnom Penh.
    final eightPm = DateTime.utc(2026, 10, 22, 13);

    test('12-hour clock in Phnom Penh time', () {
      expect(formatTime(en, eightPm), '8:00 PM');
      expect(formatTime(en, DateTime.utc(2026, 10, 22, 2, 5)), '9:05 AM');
    });

    test('by time', () {
      expect(formatByTime(en, eightPm), 'by 8:00 PM');
      expect(formatByTime(km, eightPm), startsWith('មុនម៉ោង 8:00'));
    });
  });
}
