import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/cart.dart';

/// The cart on this device, so guests can add before signing in (App Flow
/// F3). The signed-in cart on the server and syncing the two are F16.
abstract interface class CartRepository {
  List<CartLine> read();
  Future<void> write(List<CartLine> lines);
}

/// Device storage. Overridden in `main.dart` with a loaded instance.
class SharedPrefsCartRepository implements CartRepository {
  SharedPrefsCartRepository(this._prefs);

  static const key = 'cart.lines';
  final SharedPreferences _prefs;

  @override
  List<CartLine> read() => decodeCart(_prefs.getString(key));

  @override
  Future<void> write(List<CartLine> lines) =>
      _prefs.setString(key, encodeCart(lines));
}

/// Keeps the cart for this run only (tests, and before `main` overrides).
class MemoryCartRepository implements CartRepository {
  MemoryCartRepository([List<CartLine> initial = const []])
    : _lines = [...initial];

  List<CartLine> _lines;

  @override
  List<CartLine> read() => _lines;

  @override
  Future<void> write(List<CartLine> lines) async => _lines = [...lines];
}

final cartRepositoryProvider = Provider<CartRepository>(
  (ref) => MemoryCartRepository(),
);
