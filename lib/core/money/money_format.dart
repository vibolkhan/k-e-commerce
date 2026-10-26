/// K money formatting. Amounts are integer US cents, VAT included; KHR is a
/// display-only equivalent — what the customer pays is always decided by the
/// server in USD.
///
/// The format is the same in every UI language (Latin digits, comma
/// grouping): `$49.00` and `200,900`. Only the words around them are
/// translated, e.g. `AppLocalizations.uiKhrApprox` ("≈ KHR {amount}").
library;

import '../l10n/generated/app_localizations.dart';

/// Riel per US dollar used until the settings rate loads, or when it can't.
const kDefaultKhrRate = 4100;

/// Riel amounts are rounded to this, the smallest note in circulation.
const kKhrRounding = 100;

/// `4900` → `$49.00`, `123450` → `$1,234.50`, `-200` → `-$2.00`.
String formatUsd(int cents) {
  final abs = cents.abs();
  final text =
      '\$${_group(abs ~/ 100)}.${(abs % 100).toString().padLeft(2, '0')}';
  return cents < 0 ? '-$text' : text;
}

/// US cents to riel at [rate] riel per dollar, rounded half away from zero
/// to the nearest [kKhrRounding] riel. `usdCentsToKhr(4900, 4100)` → 200900.
int usdCentsToKhr(int cents, int rate) {
  final hundredthsOfRiel = cents.abs() * rate;
  const step = kKhrRounding * 100;
  final riel = (hundredthsOfRiel + step ~/ 2) ~/ step * kKhrRounding;
  return cents < 0 ? -riel : riel;
}

/// `200900` → `200,900`.
String formatKhrAmount(int riel) =>
    riel < 0 ? '-${_group(-riel)}' : _group(riel);

/// The riel line under a USD price: "≈ KHR 200,900" (localised).
String formatKhr(AppLocalizations l10n, int cents, {required int rate}) =>
    l10n.uiKhrApprox(formatKhrAmount(usdCentsToKhr(cents, rate)));

String _group(int value) {
  final digits = value.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}
