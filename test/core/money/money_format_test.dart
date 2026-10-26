import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/core/l10n/generated/app_localizations.dart';
import 'package:k_e_commerce/core/money/money_format.dart';

void main() {
  group('formatUsd', () {
    test('two decimals with a dollar sign', () {
      expect(formatUsd(4900), r'$49.00');
      expect(formatUsd(5), r'$0.05');
      expect(formatUsd(0), r'$0.00');
      expect(formatUsd(1299), r'$12.99');
    });

    test('groups thousands', () {
      expect(formatUsd(123450), r'$1,234.50');
      expect(formatUsd(100000000), r'$1,000,000.00');
    });

    test('negative amounts (refunds, discounts)', () {
      expect(formatUsd(-200), r'-$2.00');
    });
  });

  group('usdCentsToKhr', () {
    test(r'$49.00 at the default rate is 200,900', () {
      expect(kDefaultKhrRate, 4100);
      expect(usdCentsToKhr(4900, kDefaultKhrRate), 200900);
    });

    test('rounds to the nearest 100 riel', () {
      expect(usdCentsToKhr(1299, 4100), 53300); // 53,259
      expect(usdCentsToKhr(101, 4100), 4100); // 4,141
      expect(usdCentsToKhr(1, 4100), 0); // 41
    });

    test('rounds halves away from zero', () {
      // $0.50 at 4,100 = 2,050 riel exactly half-way.
      expect(usdCentsToKhr(50, 4100), 2100);
      expect(usdCentsToKhr(-50, 4100), -2100);
    });

    test('uses the given rate', () {
      expect(usdCentsToKhr(4900, 4000), 196000);
      expect(usdCentsToKhr(100, 4125), 4100); // 4,125
    });

    test('zero and large amounts', () {
      expect(usdCentsToKhr(0, 4100), 0);
      // 4,099,999,959 riel.
      expect(usdCentsToKhr(99999999, 4100), 4100000000);
    });
  });

  group('formatKhr', () {
    test('amount uses Latin digits and commas', () {
      expect(formatKhrAmount(200900), '200,900');
      expect(formatKhrAmount(900), '900');
      expect(formatKhrAmount(-4100), '-4,100');
    });

    test('English wording', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(formatKhr(l10n, 4900, rate: 4100), '≈ KHR 200,900');
    });

    test('Khmer wording keeps the same digits', () {
      final l10n = lookupAppLocalizations(const Locale('km'));
      expect(formatKhr(l10n, 4900, rate: 4100), '≈ 200,900 រៀល');
    });
  });
}
