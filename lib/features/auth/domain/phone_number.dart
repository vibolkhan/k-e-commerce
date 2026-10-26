/// Cambodian mobile numbers (+855 is the only market). Mirrors
/// `supabase/functions/_shared/phone.ts` so the app rejects what the server
/// would reject before a round trip.
abstract final class KhPhone {
  static const countryCode = '+855';

  /// E.164 (`+85512345678`) for what people type — "012 345 678",
  /// "12345678", "+855 12 345 678" — or null when it isn't a mobile number.
  static String? normalize(String input) {
    var digits = input.replaceAll(RegExp(r'[\s\-().]'), '');
    if (digits.startsWith('+')) digits = digits.substring(1);
    if (!RegExp(r'^\d+$').hasMatch(digits)) return null;
    if (digits.startsWith('855')) digits = digits.substring(3);
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (!RegExp(r'^[1-9]\d{7,8}$').hasMatch(digits)) return null;
    return '$countryCode$digits';
  }

  /// `+855 12 345 678` / `+855 97 123 4567` for display (S-05 "Sent to").
  static String display(String e164) {
    final local = e164.startsWith(countryCode)
        ? e164.substring(countryCode.length)
        : e164;
    if (local.length < 8) return e164;
    // 2-digit operator prefix, then 3 + 3 (8 digits) or 3 + 4 (9 digits).
    return '$countryCode ${local.substring(0, 2)} '
        '${local.substring(2, 5)} ${local.substring(5)}';
  }
}

/// Lower-cased, trimmed email, or null when it doesn't look like one.
String? normalizeEmail(String input) {
  final email = input.trim().toLowerCase();
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ? email : null;
}
