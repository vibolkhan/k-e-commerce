import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/cart_repository.dart';
import '../domain/cart.dart';

/// The shopper's cart lines.
class CartController extends Notifier<List<CartLine>> {
  @override
  List<CartLine> build() => ref.watch(cartRepositoryProvider).read();

  /// Adds [qty] of a variant, kept within [max] for the line.
  Future<void> add({
    required String productId,
    required String variantId,
    required int qty,
    required int max,
  }) async {
    state = addLine(
      state,
      CartLine(variantId: variantId, productId: productId, qty: qty),
      max: max,
    );
    await ref.read(cartRepositoryProvider).write(state);
  }
}

final cartProvider = NotifierProvider<CartController, List<CartLine>>(
  CartController.new,
);

/// Items in the cart, for the cart badge.
final cartCountProvider = Provider<int>(
  (ref) => ref.watch(cartProvider).fold(0, (n, l) => n + l.qty),
);
