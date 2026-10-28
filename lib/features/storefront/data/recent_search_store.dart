import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/search.dart';

/// A guest's recent searches, kept on the device. Signed-in shoppers' are
/// kept per account on the server (`search_history`).
abstract interface class RecentSearchStore {
  List<String> read();
  Future<void> push(String query);
  Future<void> clear();
}

/// Device storage. Overridden in `main.dart` with a loaded instance.
class SharedPrefsRecentSearchStore implements RecentSearchStore {
  SharedPrefsRecentSearchStore(this._prefs);

  static const key = 'search.recent';
  final SharedPreferences _prefs;

  @override
  List<String> read() => _prefs.getStringList(key) ?? const [];

  @override
  Future<void> push(String query) =>
      _prefs.setStringList(key, pushRecent(read(), query));

  @override
  Future<void> clear() => _prefs.remove(key);
}

/// Keeps searches for this run only (tests, and before `main` overrides).
class MemoryRecentSearchStore implements RecentSearchStore {
  MemoryRecentSearchStore([List<String> initial = const []])
    : _recent = [...initial];

  List<String> _recent;

  @override
  List<String> read() => _recent;

  @override
  Future<void> push(String query) async => _recent = pushRecent(_recent, query);

  @override
  Future<void> clear() async => _recent = [];
}

final recentSearchStoreProvider = Provider<RecentSearchStore>(
  (ref) => MemoryRecentSearchStore(),
);
