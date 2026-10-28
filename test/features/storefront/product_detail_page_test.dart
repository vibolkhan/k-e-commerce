import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/app.dart';
import 'package:k_e_commerce/core/config/app_config.dart';
import 'package:k_e_commerce/core/config/bootstrap.dart';
import 'package:k_e_commerce/core/router/app_role.dart';
import 'package:k_e_commerce/core/router/app_router.dart';
import 'package:k_e_commerce/core/time/phnom_penh_time.dart';
import 'package:k_e_commerce/core/ui/k_ui.dart';
import 'package:k_e_commerce/core/ui/pages/error_page.dart';
import 'package:k_e_commerce/features/auth/domain/profile.dart';
import 'package:k_e_commerce/features/auth/presentation/auth_providers.dart';
import 'package:k_e_commerce/features/cart/data/cart_repository.dart';
import 'package:k_e_commerce/features/storefront/data/product_detail_repository.dart';
import 'package:k_e_commerce/features/storefront/domain/product_detail.dart';
import 'package:k_e_commerce/features/storefront/domain/reviews.dart';
import 'package:k_e_commerce/features/storefront/domain/storefront.dart';

import '../../helpers.dart';
import '../auth/fake_auth_repository.dart';
import 'fakes.dart';
import 'product_detail_fixtures.dart';

const _dara = Profile(
  id: 'c',
  role: AppRole.customer,
  fullName: 'Dara Sok',
  email: 'dara@k.example',
);
const _sokha = Profile(
  id: 'b',
  role: AppRole.business,
  fullName: 'Sokha Chan',
  email: 'sokha@k.example',
);

const _phone = Size(390, 844);
const _web = Size(1280, 900);

/// The whole app opened on a product page, as a guest or [email].
Future<({ProviderContainer container, MemoryCartRepository cart})> pumpProduct(
  WidgetTester tester, {
  Map<String, ProductDetail>? products,
  String id = 'p-hp',
  String? email,
  DateTime? now,
  Size size = _phone,
  FakeStorefrontRepository? store,
  ProductReviews reviews = ProductReviews.none,
  String shell = '/customer',
  FakeProductDetailRepository? detailRepo,
}) async {
  setViewSize(tester, size);
  final auth = FakeAuthRepository(
    accounts: {'dara@k.example': _dara, 'sokha@k.example': _sokha},
  );
  addTearDown(auth.dispose);
  if (email != null) await auth.signInWithPassword(email, 'password123');
  final cart = MemoryCartRepository();
  final at = now ?? storeNow;
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        const AppConfig(env: AppEnv.dev, supabaseUrl: '', supabaseAnonKey: ''),
      ),
      onboardedDevice,
      authRepositoryProvider.overrideWithValue(auth),
      clockProvider.overrideWithValue(() => at),
      ...storefrontOverrides(store ?? FakeStorefrontRepository(serverNow: at)),
      productDetailRepositoryProvider.overrideWithValue(
        detailRepo ??
            FakeProductDetailRepository(
              products ?? {'p-hp': detailFrom(headphonesJson())},
            ),
      ),
      reviewsRepositoryProvider.overrideWithValue(
        FakeReviewsRepository(reviews),
      ),
      cartRepositoryProvider.overrideWithValue(cart),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const KApp()),
  );
  await tester.pumpAndSettle();
  container.read(routerProvider).go('$shell/products/$id');
  await tester.pumpAndSettle();
  return (container: container, cart: cart);
}

String _location(ProviderContainer c) => c.read(routerProvider).state.uri.path;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  // ensureVisible puts it at the top, under the page's top bar.
  final scroll = find.byKey(const Key('pd-scroll'));
  final top = tester.getRect(finder).top;
  if (top < 120 && scroll.evaluate().isNotEmpty && !_inSheet(finder)) {
    await tester.drag(scroll, Offset(0, 140 - top));
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

bool _inSheet(Finder finder) => find
    .ancestor(of: finder, matching: find.byKey(const Key('pd-options-sheet')))
    .evaluate()
    .isNotEmpty;

Finder _rich(String text) => find.textContaining(text, findRichText: true);

void main() {
  setUp(hideKToast);

  group('C-05 Product detail', () {
    testWidgets('shows stock, rating, price in USD and KHR and delivery', (
      tester,
    ) async {
      await pumpProduct(tester);
      expect(find.text('Wireless Headphones Pro'), findsWidgets);
      expect(find.text('In stock'), findsOneWidget);
      expect(find.text('Only 11 left'), findsOneWidget);
      expect(find.text('4.6'), findsOneWidget);
      expect(find.text('128 reviews'), findsOneWidget);
      expect(find.text(r'$49.00'), findsOneWidget);
      expect(find.text('≈ KHR 200,900'), findsOneWidget);
      expect(find.text('Prices include VAT.'), findsOneWidget);
      expect(_rich('Colour: Black'), findsOneWidget);
      expect(find.text('Get it today'), findsOneWidget);
      expect(
        find.text(
          r'Order within 4h 35m · delivered by 8:00 PM. Free over $50.',
        ),
        findsOneWidget,
      );
      expect(_rich('3-day returns.'), findsOneWidget);
      expect(find.text('Pay with KHQR or cash on delivery.'), findsOneWidget);
      expect(find.text('1 / 1'), findsOneWidget);
      expect(find.text('Add to cart'), findsOneWidget);
    });

    testWidgets('Description has the text, highlights and related row', (
      tester,
    ) async {
      await pumpProduct(tester);
      expect(find.textContaining('Quiet, comfortable'), findsOneWidget);
      expect(
        find.text('Active noise cancelling with transparency mode'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('You may also like'));
      await tester.pumpAndSettle();
      expect(find.text('Bluetooth Speaker Mini'), findsOneWidget);
      expect(find.text('Smart Watch Active 2'), findsOneWidget);
    });

    testWidgets('choosing a colour updates price and stock', (tester) async {
      await pumpProduct(
        tester,
        products: {'p-hp': detailFrom(headphonesJson(whitePrice: 5200))},
      );
      await _tap(tester, find.byKey(const ValueKey('swatch-White')));
      expect(find.text(r'$52.00'), findsOneWidget);
      expect(find.text('Only 11 left'), findsNothing);
      expect(find.text('In stock'), findsOneWidget);
      expect(_rich('Colour: White'), findsOneWidget);
    });

    testWidgets('sold-out colours cannot be chosen', (tester) async {
      await pumpProduct(tester);
      final sky = tester.getSemantics(find.byKey(const ValueKey('swatch-Sky')));
      expect(sky.label, 'Sky, out of stock');
      await _tap(tester, find.byKey(const ValueKey('swatch-Sky')));
      expect(_rich('Colour: Black'), findsOneWidget);
      expect(find.text('Only 11 left'), findsOneWidget);
    });

    testWidgets('the rating opens the Reviews tab', (tester) async {
      await pumpProduct(tester);
      await _tap(tester, find.byKey(const Key('pd-rating')));
      expect(find.text('No reviews to show yet'), findsOneWidget);
    });

    testWidgets('after the cut-off it promises tomorrow', (tester) async {
      await pumpProduct(tester, now: DateTime.utc(2026, 10, 27, 9)); // 4 PM
      expect(find.text('Get it tomorrow'), findsOneWidget);
      expect(
        find.text(r"Today's 3:00 PM cut-off has passed. Free over $50."),
        findsOneWidget,
      );
    });

    testWidgets('signed-in shoppers see where it goes', (tester) async {
      await pumpProduct(
        tester,
        email: 'dara@k.example',
        store: FakeStorefrontRepository(
          addressList: const [
            DeliverTo(id: 'a1', label: 'Home', area: 'Toul Kork'),
          ],
        ),
      );
      expect(
        find.text(
          r'Order within 4h 35m · delivered by 8:00 PM to Toul Kork. '
          r'Free over $50.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a sold-out product cannot be added', (tester) async {
      final json = headphonesJson();
      for (final v in json['variants'] as List) {
        v['available'] = 0;
      }
      await pumpProduct(tester, products: {'p-hp': detailFrom(json)});
      expect(find.text('Out of stock'), findsOneWidget);
      final add = tester.widget<KButton>(find.byKey(const Key('pd-add')));
      expect(add.label, 'Sold out');
      expect(add.onPressed, isNull);
    });

    testWidgets('an unknown product says it is not found', (tester) async {
      await pumpProduct(tester, id: 'p-none');
      expect(find.byType(ErrorPage), findsOneWidget);
    });

    testWidgets('a failed load can be retried', (tester) async {
      final repo = FakeProductDetailRepository({
        'p-hp': detailFrom(headphonesJson()),
      }, fail: true);
      await pumpProduct(tester, detailRepo: repo);
      expect(
        find.text("Couldn't load this. Check your connection and try again."),
        findsOneWidget,
      );
      repo.fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Only 11 left'), findsOneWidget);
    });

    testWidgets('fits the web layout', (tester) async {
      await pumpProduct(tester, size: _web);
      expect(tester.takeException(), isNull);
      expect(find.text('Only 11 left'), findsOneWidget);
    });
  });

  group('C-05a Specifications and C-05b Reviews', () {
    testWidgets('Specifications lists brand, colours and the rows', (
      tester,
    ) async {
      await pumpProduct(tester);
      await _tap(tester, find.text('Specifications'));
      expect(find.byKey(const Key('pd-specs')), findsOneWidget);
      expect(find.text('Brand'), findsOneWidget);
      expect(find.text('Sonora'), findsOneWidget);
      expect(find.text('Model'), findsOneWidget);
      expect(find.text('WH-PRO'), findsOneWidget);
      expect(find.text('Black, White, Sky'), findsOneWidget);
      expect(find.text('250 g'), findsOneWidget);
      expect(
        find.text(
          'Details come from the brand and may change. Ask us in chat if '
          'you need anything else.',
        ),
        findsOneWidget,
      );
      expect(find.text(r'Add to cart · $49.00'), findsOneWidget);
    });

    testWidgets('Reviews shows the empty state until reviews arrive', (
      tester,
    ) async {
      await pumpProduct(tester);
      await _tap(tester, find.text('Reviews'));
      expect(find.byKey(const Key('pd-reviews-empty')), findsOneWidget);
      expect(find.text(r'Add to cart · $49.00'), findsOneWidget);
    });

    testWidgets('Reviews shows the summary and cards when there are some', (
      tester,
    ) async {
      await pumpProduct(
        tester,
        reviews: ProductReviews(
          average: 4.6,
          total: 128,
          byStars: const {5: 92, 4: 24, 3: 7, 2: 3, 1: 2},
          withPhotos: 24,
          items: [
            Review(
              id: 'r1',
              author: 'Sreymom K.',
              rating: 5,
              createdAt: DateTime.utc(2026, 10, 18),
              variantLabel: 'Colour: Black',
              body: 'Really quiet on the bus.',
              helpful: 12,
            ),
            Review(
              id: 'r2',
              author: 'Rithy H.',
              rating: 4,
              createdAt: DateTime.utc(2026, 10, 15),
              body: 'Comfortable for long calls.',
              reply: 'Thanks for the feedback, Rithy.',
            ),
          ],
        ),
      );
      await _tap(tester, find.text('Reviews'));
      expect(find.text('92'), findsOneWidget);
      expect(find.text('With photos · 24'), findsOneWidget);
      expect(find.text('Sreymom K.'), findsOneWidget);
      expect(find.text('Colour: Black · Verified purchase'), findsOneWidget);
      expect(find.text('Helpful (12)'), findsOneWidget);
      expect(find.text('Reply from K'), findsOneWidget);
      expect(find.text('See all 128 reviews'), findsOneWidget);
      await _tap(tester, find.widgetWithText(KChip, '5'));
      expect(find.text('Rithy H.'), findsNothing);
    });
  });

  group('C-05c Choose options and C-05d toast', () {
    testWidgets('the sheet keeps to the per-order limit and adds to the cart', (
      tester,
    ) async {
      final app = await pumpProduct(tester);
      await _tap(tester, find.byKey(const Key('pd-add')));
      expect(find.byKey(const Key('pd-options-sheet')), findsOneWidget);
      expect(find.text('11 in stock'), findsOneWidget);
      expect(find.text('Max. 5 per order'), findsOneWidget);
      expect(_rich('Order within 4h 35m to get it today.'), findsOneWidget);
      expect(find.text('Sky · sold out'), findsOneWidget);
      for (var i = 0; i < 7; i++) {
        await tester.tap(find.bySemanticsLabel('Increase'));
        await tester.pump();
      }
      final qty = tester.widget<KQtyStepper>(find.byKey(const Key('pd-qty')));
      expect(qty.value, 5);
      expect(find.text(r'Add to cart · $245.00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pd-sheet-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pd-options-sheet')), findsNothing);
      expect(find.text('Added to cart'), findsOneWidget);
      expect(find.text('Wireless Headphones Pro · Black · 5'), findsOneWidget);
      expect(find.text('View cart'), findsOneWidget);
      expect(app.cart.read().single.variantId, 'v-blk');
      expect(app.cart.read().single.qty, 5);
      expect(find.bySemanticsLabel('Cart, 5 items'), findsOneWidget);
      hideKToast();
    });

    testWidgets('choices in the sheet carry back to the page', (tester) async {
      await pumpProduct(
        tester,
        products: {'p-hp': detailFrom(headphonesJson(whitePrice: 5200))},
      );
      await _tap(tester, find.byKey(const Key('pd-add')));
      await _tap(tester, find.byKey(const ValueKey('option-White')));
      expect(find.text('40 in stock'), findsOneWidget);
      await _tap(tester, find.bySemanticsLabel('Close'));
      expect(find.text(r'$52.00'), findsOneWidget);
    });

    testWidgets('a full line cannot be added again', (tester) async {
      final app = await pumpProduct(tester);
      for (var i = 0; i < 2; i++) {
        await _tap(tester, find.byKey(const Key('pd-add')));
        for (var j = 0; j < 4; j++) {
          await tester.tap(find.bySemanticsLabel('Increase'));
          await tester.pump();
        }
        await tester.tap(find.byKey(const Key('pd-sheet-add')));
        await tester.pumpAndSettle();
        hideKToast();
      }
      expect(app.cart.read().single.qty, 5);
      await _tap(tester, find.byKey(const Key('pd-add')));
      expect(
        find.text('You already have the most you can order.'),
        findsOneWidget,
      );
      final add = tester.widget<KButton>(find.byKey(const Key('pd-sheet-add')));
      expect(add.onPressed, isNull);
    });

    testWidgets('View cart opens the cart', (tester) async {
      final app = await pumpProduct(tester);
      await _tap(tester, find.byKey(const Key('pd-add')));
      await tester.tap(find.byKey(const Key('pd-sheet-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View cart'));
      await tester.pumpAndSettle();
      expect(_location(app.container), '/customer/cart');
    });
  });

  group('C-05e Image viewer and the heart', () {
    testWidgets('the photo pill opens the viewer and close returns', (
      tester,
    ) async {
      await pumpProduct(tester);
      await _tap(tester, find.byKey(const Key('pd-open-viewer')));
      expect(find.byKey(const Key('pd-viewer')), findsOneWidget);
      expect(find.text('Pinch to zoom'), findsOneWidget);
      await _tap(tester, find.bySemanticsLabel('Close photo viewer'));
      expect(find.byKey(const Key('pd-viewer')), findsNothing);
      expect(find.text('Only 11 left'), findsOneWidget);
    });

    testWidgets('guests tapping the heart are asked to sign in', (
      tester,
    ) async {
      final app = await pumpProduct(tester);
      await _tap(tester, find.byKey(const Key('pd-wishlist')));
      expect(_location(app.container), '/sign-in');
    });

    testWidgets('signed-in shoppers hear the wishlist is coming', (
      tester,
    ) async {
      await pumpProduct(tester, email: 'dara@k.example');
      await _tap(tester, find.byKey(const Key('pd-wishlist')));
      expect(
        find.text('Saving to your wishlist is coming soon.'),
        findsOneWidget,
      );
      hideKToast();
    });
  });

  testWidgets('business buyers keep the B-00a placeholder until F26', (
    tester,
  ) async {
    await pumpProduct(tester, email: 'sokha@k.example', shell: '/business');
    expect(
      find.text('This screen (B-00a) arrives in a later update.'),
      findsOneWidget,
    );
  });
}
