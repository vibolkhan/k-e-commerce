import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/bootstrap.dart';
import '../utils/log.dart';

/// Where the language choice is kept on this device. Reads are synchronous so
/// the first frame already uses the saved language.
abstract interface class LocaleStore {
  String? read();
  Future<void> write(String code);
}

/// Device storage. Overridden in `main.dart` with a loaded instance.
class SharedPrefsLocaleStore implements LocaleStore {
  SharedPrefsLocaleStore(this._prefs);

  static const key = 'locale';
  final SharedPreferences _prefs;

  @override
  String? read() => _prefs.getString(key);

  @override
  Future<void> write(String code) => _prefs.setString(key, code);
}

/// Keeps the choice for this run only (tests, and before `main` overrides).
class MemoryLocaleStore implements LocaleStore {
  MemoryLocaleStore([this._code]);

  String? _code;

  @override
  String? read() => _code;

  @override
  Future<void> write(String code) async => _code = code;
}

final localeStoreProvider = Provider<LocaleStore>((ref) => MemoryLocaleStore());

/// The signed-in user's saved language, so it follows them across devices.
abstract interface class LocaleAccountSync {
  /// Emits the account's saved language code (null if none) each time a user
  /// signs in or a session is restored.
  Stream<String?> get signedIn;

  /// Saves [code] to the signed-in account; does nothing for guests.
  Future<void> save(String code);
}

/// Guests and offline builds: nothing to sync.
class NoLocaleAccountSync implements LocaleAccountSync {
  const NoLocaleAccountSync();

  @override
  Stream<String?> get signedIn => const Stream.empty();

  @override
  Future<void> save(String code) async {}
}

/// Stores the language in the Supabase auth user's metadata (`locale`).
class SupabaseLocaleAccountSync implements LocaleAccountSync {
  SupabaseLocaleAccountSync(this._auth);

  static const metadataKey = 'locale';
  final GoTrueClient _auth;

  @override
  Stream<String?> get signedIn => _auth.onAuthStateChange
      .where(
        (state) =>
            state.session != null &&
            (state.event == AuthChangeEvent.signedIn ||
                state.event == AuthChangeEvent.initialSession),
      )
      .map(
        (state) => state.session!.user.userMetadata?[metadataKey] as String?,
      );

  @override
  Future<void> save(String code) async {
    if (_auth.currentUser == null) return;
    try {
      await _auth.updateUser(UserAttributes(data: {metadataKey: code}));
    } catch (e) {
      // The device copy is already saved; the account catches up next time.
      log('Could not save language to account: $e');
    }
  }
}

final localeAccountSyncProvider = Provider<LocaleAccountSync>((ref) {
  if (!ref.watch(appConfigProvider).isSupabaseConfigured) {
    return const NoLocaleAccountSync();
  }
  return SupabaseLocaleAccountSync(Supabase.instance.client.auth);
});
