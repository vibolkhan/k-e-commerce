import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/features/cart/data/cart_repository.dart';
import 'package:k_e_commerce/features/cart/domain/cart.dart';
import 'package:k_e_commerce/features/cart/presentation/cart_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _black = CartLine(variantId: 'v-blk', productId: 'p-hp', qty: 1);

void main() {
  group('addLine', () {
    test('adds a new line', () {
      expect(addLine(const [], _black, max: 5), [_black]);
    });

    test('merges the same variant and keeps within the max', () {
      var lines = addLine(const [], _black.withQty(3), max: 5);
      lines = addLine(lines, _black.withQty(4), max: 5);
      expect(lines, [_black.withQty(5)]);
    });

    test('keeps other lines and their order', () {
      const white = CartLine(variantId: 'v-wht', productId: 'p-hp', qty: 2);
      final lines = addLine(addLine(const [], _black, max: 5), white, max: 5);
      expect(addLine(lines, _black, max: 5), [_black.withQty(2), white]);
      expect(qtyInCart(lines, 'v-wht'), 2);
      expect(qtyInCart(lines, 'v-none'), 0);
    });
  });

  test('encodes and decodes, ignoring broken data', () {
    final raw = encodeCart([_black]);
    expect(decodeCart(raw), [_black]);
    expect(decodeCart(null), isEmpty);
    expect(decodeCart('not json'), isEmpty);
  });

  test('the device cart survives a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await SharedPrefsCartRepository(prefs).write([_black]);
    expect(SharedPrefsCartRepository(prefs).read(), [_black]);
  });

  test('the cart provider adds and counts', () async {
    final container = ProviderContainer(
      overrides: [
        cartRepositoryProvider.overrideWithValue(MemoryCartRepository()),
      ],
    );
    addTearDown(container.dispose);
    final cart = container.read(cartProvider.notifier);
    await cart.add(productId: 'p-hp', variantId: 'v-blk', qty: 2, max: 5);
    await cart.add(productId: 'p-hp', variantId: 'v-wht', qty: 1, max: 5);
    expect(container.read(cartCountProvider), 3);
    expect(container.read(cartRepositoryProvider).read(), hasLength(2));
  });
}
