import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'locale_store.dart';
import 'supported_languages.dart';

/// The app language the user picked; null follows the device. Saved on the
/// device for everyone and on the account when signed in. On sign-in the
/// account's language wins; if it has none, the device choice is uploaded.
class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() {
    final sync = ref.watch(localeAccountSyncProvider);
    final sub = sync.signedIn.listen(_onSignedIn);
    ref.onDispose(sub.cancel);
    return appLanguageFor(ref.watch(localeStoreProvider).read())?.locale;
  }

  /// Switches the UI language now and saves the choice.
  Future<void> setLocale(Locale locale) async {
    final language = appLanguageFor(locale.languageCode);
    if (language == null) return;
    state = language.locale;
    await ref.read(localeStoreProvider).write(language.code);
    await ref.read(localeAccountSyncProvider).save(language.code);
  }

  Future<void> _onSignedIn(String? accountCode) async {
    final fromAccount = appLanguageFor(accountCode);
    if (fromAccount != null) {
      state = fromAccount.locale;
      await ref.read(localeStoreProvider).write(fromAccount.code);
    } else if (state != null) {
      await ref.read(localeAccountSyncProvider).save(state!.languageCode);
    }
  }
}

final localeControllerProvider = NotifierProvider<LocaleController, Locale?>(
  LocaleController.new,
);
