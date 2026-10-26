import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

/// A language the app ships in.
class AppLanguage {
  const AppLanguage(this.locale, this.nativeName);

  final Locale locale;

  /// The language's own name (endonym), shown the same in every UI language
  /// so people can find theirs.
  final String nativeName;

  String get code => locale.languageCode;

  /// The language's name in the current UI language.
  String name(AppLocalizations l10n) => switch (code) {
    'km' => l10n.languageKhmer,
    _ => l10n.languageEnglish,
  };
}

/// In the order the language pickers list them (S-02, S-08c): Khmer first.
const appLanguages = [
  AppLanguage(Locale('km'), 'ខ្មែរ'),
  AppLanguage(Locale('en'), 'English'),
];

/// The supported language for [code], or null.
AppLanguage? appLanguageFor(String? code) {
  for (final language in appLanguages) {
    if (language.code == code) return language;
  }
  return null;
}
