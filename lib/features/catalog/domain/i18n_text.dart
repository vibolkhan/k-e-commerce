/// Translatable catalogue text: jsonb `{"en": ..., "km": ...}` (F04). English
/// is required; Khmer may be missing until translated (A-05a "Translation
/// missing").
class I18nText {
  const I18nText({this.en = '', this.km = ''});

  factory I18nText.fromJson(Object? json) => switch (json) {
    final Map<dynamic, dynamic> m => I18nText(
      en: m['en'] is String ? m['en'] as String : '',
      km: m['km'] is String ? m['km'] as String : '',
    ),
    final String s => I18nText(en: s),
    _ => const I18nText(),
  };

  static const empty = I18nText();

  final String en;
  final String km;

  bool get isEmpty => en.trim().isEmpty && km.trim().isEmpty;

  /// English is there but Khmer is not.
  bool get missingKm => en.trim().isNotEmpty && km.trim().isEmpty;

  /// The text for [languageCode], falling back to English.
  String of(String languageCode) =>
      languageCode == 'km' && km.trim().isNotEmpty ? km : en;

  I18nText copyWith({String? en, String? km}) =>
      I18nText(en: en ?? this.en, km: km ?? this.km);

  Map<String, String> toJson() => {
    if (en.trim().isNotEmpty) 'en': en.trim(),
    if (km.trim().isNotEmpty) 'km': km.trim(),
  };

  @override
  bool operator ==(Object other) =>
      other is I18nText && other.en == en && other.km == km;

  @override
  int get hashCode => Object.hash(en, km);

  @override
  String toString() => 'I18nText($en | $km)';
}
