import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/app.dart';
import 'package:k_e_commerce/core/config/app_config.dart';
import 'package:k_e_commerce/core/config/bootstrap.dart';
import 'package:k_e_commerce/core/router/app_role.dart';
import 'package:k_e_commerce/core/router/app_router.dart';
import 'package:k_e_commerce/core/router/app_routes.dart';
import 'package:k_e_commerce/core/time/phnom_penh_time.dart';
import 'package:k_e_commerce/features/auth/domain/profile.dart';
import 'package:k_e_commerce/features/auth/presentation/auth_providers.dart';
import 'package:k_e_commerce/features/catalog/domain/i18n_text.dart';
import 'package:k_e_commerce/features/storefront/domain/browse.dart';
import 'package:k_e_commerce/features/storefront/domain/storefront.dart';

import '../../helpers.dart';
import '../auth/fake_auth_repository.dart';
import 'fakes.dart';

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

const phone = Size(390, 844);
const web = Size(1280, 900);

const _sameDayBanner = HomeBanner(
  id: 'b1',
  title: I18nText(en: 'Order by 3 PM, get it today'),
  subtitle: I18nText(en: 'Free delivery on orders over \$50 in Phnom Penh.'),
  cta: I18nText(en: 'Shop now'),
  badge: I18nText(en: 'Same-day delivery'),
  linkType: BannerLinkType.collection,
  linkTarget: 'best-sellers',
);

/// The whole app with a fake storefront, as a guest or signed in as
/// [email], opened at [location].
Future<ProviderContainer> pumpStore(
  WidgetTester tester, {
  FakeStorefrontRepository? repo,
  String? email,
  DateTime? now,
  Size size = phone,
  String? location,
}) async {
  setViewSize(tester, size);
  final auth = FakeAuthRepository(
    accounts: {'dara@k.example': _dara, 'sokha@k.example': _sokha},
  );
  addTearDown(auth.dispose);
  if (email != null) await auth.signInWithPassword(email, 'password123');
  final store = repo ?? FakeStorefrontRepository(bannerList: [_sameDayBanner]);
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        const AppConfig(env: AppEnv.dev, supabaseUrl: '', supabaseAnonKey: ''),
      ),
      onboardedDevice,
      authRepositoryProvider.overrideWithValue(auth),
      clockProvider.overrideWithValue(() => now ?? storeNow),
      ...storefrontOverrides(store),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const KApp()),
  );
  await tester.pumpAndSettle();
  if (location != null) {
    container.read(routerProvider).go(location);
    await tester.pumpAndSettle();
  }
  return container;
}

/// The top page's path, pushed pages included.
String _location(ProviderContainer c) => c.read(routerProvider).state.uri.path;

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('C-01 Home', () {
    testWidgets('guests see banners, the countdown and the rails', (
      tester,
    ) async {
      await pumpStore(tester);
      expect(storeHome('customer'), findsOneWidget);
      expect(find.text('Phnom Penh'), findsOneWidget);
      expect(find.text('Order by 3 PM, get it today'), findsOneWidget);
      expect(
        find.textContaining(
          'Order within 4h 35m for delivery today',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text('Shop by category'), findsOneWidget);
      expect(find.text('Electronics'), findsOneWidget);
      expect(find.text('Best sellers'), findsOneWidget);
      expect(find.text(r'$49.00'), findsOneWidget);
      expect(find.text('≈ KHR 200,900'), findsOneWidget);
      expect(find.text('Buying for a business?'), findsOneWidget);
      expect(find.text('New arrivals'), findsOneWidget);
      expect(find.text('New'), findsNothing); // the new arrival is sold out
      expect(find.text('Sold out'), findsOneWidget);
    });

    testWidgets('after the cut-off it promises tomorrow', (tester) async {
      final repo = FakeStorefrontRepository(
        serverNow: DateTime.utc(2026, 10, 27, 9), // 4:00 PM
      );
      await pumpStore(tester, repo: repo, now: DateTime.utc(2026, 10, 27, 9));
      expect(
        find.textContaining(
          'cut-off has passed. Order now for delivery tomorrow',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('the countdown uses the server clock', (tester) async {
      // Device says 10:25 AM; the server says 2:30 PM.
      final repo = FakeStorefrontRepository(
        serverNow: DateTime.utc(2026, 10, 27, 7, 30),
      );
      await pumpStore(tester, repo: repo);
      expect(
        find.textContaining('Order within 30m', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('a banner opens its collection', (tester) async {
      final c = await pumpStore(tester);
      await tester.tap(find.text('Order by 3 PM, get it today'));
      await tester.pumpAndSettle();
      expect(_location(c), AppRoutes.collection('/customer', 'best-sellers'));
      expect(find.text('2 products'), findsOneWidget);
    });

    testWidgets('a category shortcut opens its list in the Categories tab', (
      tester,
    ) async {
      final c = await pumpStore(tester);
      await tapVisible(tester, find.text('Kitchen'));
      expect(_location(c), '/customer/categories/kitchen');
      expect(find.text('Ceramic Coffee Mug Set'), findsOneWidget);
    });

    testWidgets('search opens C-04', (tester) async {
      final c = await pumpStore(tester);
      await tester.tap(find.byKey(const Key('home-search')));
      await tester.pumpAndSettle();
      expect(_location(c), '/customer/search');
    });

    testWidgets('signed-in shoppers deliver to their default address', (
      tester,
    ) async {
      final repo = FakeStorefrontRepository(
        addressList: const [
          DeliverTo(id: 'a1', label: 'Home', area: 'Toul Kork'),
          DeliverTo(id: 'a2', label: 'Office', area: 'Daun Penh'),
        ],
      );
      await pumpStore(tester, repo: repo, email: 'dara@k.example');
      expect(find.text('Home · Toul Kork'), findsOneWidget);

      await tester.tap(find.byKey(const Key('deliver-to')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Office'));
      await tester.pumpAndSettle();
      expect(find.text('Office · Daun Penh'), findsOneWidget);
    });

    testWidgets('guests are asked to sign in from the location pill', (
      tester,
    ) async {
      await pumpStore(tester);
      await tester.tap(find.byKey(const Key('deliver-to')));
      await tester.pumpAndSettle();
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('business buyers get quote prices and their own content', (
      tester,
    ) async {
      final repo = FakeStorefrontRepository(business: true);
      await pumpStore(tester, repo: repo, email: 'sokha@k.example');
      expect(storeHome('business'), findsOneWidget);
      expect(
        find.text('You\'ll see prices after sales sends your quote.'),
        findsOneWidget,
      );
      expect(find.text('Popular for offices'), findsOneWidget);
      expect(find.text('Price on quote'), findsWidgets);
      expect(find.textContaining(r'$'), findsNothing);
      expect(find.text('Buying for a business?'), findsNothing);
      expect(repo.bannerAudiences.toSet(), {Audience.business});
      expect(
        repo.queries.map((q) => q.collection),
        contains('popular-for-offices'),
      );
    });

    testWidgets('empty sections are hidden', (tester) async {
      final repo = FakeStorefrontRepository(products: const []);
      await pumpStore(tester, repo: repo);
      expect(find.text('Best sellers'), findsNothing);
      expect(find.text('New arrivals'), findsNothing);
      expect(find.text('Shop by category'), findsOneWidget);
    });

    testWidgets('fits the web layout', (tester) async {
      await pumpStore(tester, size: web);
      expect(tester.takeException(), isNull);
      expect(find.text('Wireless Headphones Pro'), findsOneWidget);
    });
  });

  group('C-02 Categories', () {
    testWidgets('the rail switches the pane', (tester) async {
      await pumpStore(tester, location: '/customer/categories');
      expect(find.text('Categories'), findsWidgets);
      expect(find.text('Audio'), findsOneWidget); // subcategory tile
      expect(find.text('Popular in Electronics'), findsOneWidget);
      expect(
        find.text('Delivered today if you order before 3:00 PM'),
        findsOneWidget,
      );

      await tester.tap(find.text('Kitchen'));
      await tester.pumpAndSettle();
      expect(find.text('Popular in Kitchen'), findsOneWidget);
      expect(find.text('Ceramic Coffee Mug Set'), findsOneWidget);
      expect(find.text('Audio'), findsNothing);
    });

    testWidgets('an empty category says so', (tester) async {
      await pumpStore(tester, location: '/customer/categories');
      await tester.tap(find.text('Pantry'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing here yet'), findsOneWidget);
    });

    testWidgets('a subcategory opens its product list', (tester) async {
      final c = await pumpStore(tester, location: '/customer/categories');
      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();
      expect(_location(c), '/customer/categories/audio');
      expect(find.text('2 products'), findsOneWidget);
    });

    testWidgets('is the second tab', (tester) async {
      final c = await pumpStore(tester);
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      expect(_location(c), '/customer/categories');
    });
  });

  group('C-03 Product list', () {
    testWidgets('a top category lists its subcategories too', (tester) async {
      await pumpStore(tester, location: '/customer/categories/electronics');
      expect(find.text('2 products'), findsOneWidget);
      expect(find.text('All ship same day'), findsOneWidget);
      expect(find.text('Wireless Headphones Pro'), findsOneWidget);
      expect(find.text('Bluetooth Speaker Mini'), findsOneWidget);
    });

    testWidgets('quick chips filter the list', (tester) async {
      final repo = FakeStorefrontRepository();
      await pumpStore(
        tester,
        repo: repo,
        location: '/customer/categories/audio',
      );
      await tapVisible(tester, find.byKey(const Key('chip-in-stock')));
      expect(repo.queries.last.inStock, isTrue);
      expect(find.text('1 product'), findsOneWidget);
      expect(find.text('Bluetooth Speaker Mini'), findsNothing);

      await tapVisible(tester, find.byKey(const Key('chip-under')));
      expect(repo.queries.last.maxCents, 5000);
      expect(find.text('Filters, 2'), findsNothing); // count is in semantics
      expect(repo.queries.last.activeFilterCount, 2);
    });

    testWidgets('the sort sheet reorders', (tester) async {
      final repo = FakeStorefrontRepository();
      await pumpStore(
        tester,
        repo: repo,
        location: '/customer/categories/electronics',
      );
      await tapVisible(tester, find.byKey(const Key('chip-sort')));
      expect(find.text('Sort by'), findsOneWidget);
      await tester.tap(find.text('Price: low to high'));
      await tester.tap(find.byKey(const Key('sort-apply')));
      await tester.pumpAndSettle();
      expect(repo.queries.last.sort, BrowseSort.priceAsc);
      expect(find.text('Sort: Price: low to high'), findsOneWidget);
      final speaker = tester.getTopLeft(find.text('Bluetooth Speaker Mini'));
      final headphones = tester.getTopLeft(
        find.text('Wireless Headphones Pro'),
      );
      expect(speaker.dx, lessThan(headphones.dx));
    });

    testWidgets('the filter sheet narrows by brand and resets', (tester) async {
      final repo = FakeStorefrontRepository();
      await pumpStore(
        tester,
        repo: repo,
        location: '/customer/categories/electronics',
      );
      await tapVisible(tester, find.byKey(const Key('chip-filters')));
      expect(find.text('Show 2 results'), findsOneWidget);
      expect(find.text('Same-day delivery'), findsOneWidget);

      await tester.tap(find.byKey(const Key('brand-Nimbus')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Show 1 result'), findsOneWidget);
      await tester.tap(find.byKey(const Key('filters-apply')));
      await tester.pumpAndSettle();
      expect(repo.queries.last.brands, {'Nimbus'});
      expect(find.text('Wireless Headphones Pro'), findsNothing);

      await tapVisible(tester, find.byKey(const Key('chip-filters')));
      await tester.tap(find.byKey(const Key('filters-reset')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filters-apply')));
      await tester.pumpAndSettle();
      expect(repo.queries.last.brands, isEmpty);
      expect(find.text('Wireless Headphones Pro'), findsOneWidget);
    });

    testWidgets('no matches offers to clear the filters', (tester) async {
      final repo = FakeStorefrontRepository();
      await pumpStore(
        tester,
        repo: repo,
        location: '/customer/categories/kitchen',
      );
      await tapVisible(tester, find.byKey(const Key('chip-rating')));
      await tapVisible(tester, find.byKey(const Key('chip-under')));
      expect(find.text('1 product'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('chip-in-stock')));
      expect(find.text('1 product'), findsOneWidget);

      // Kitchen's only product isn't same day.
      await tapVisible(tester, find.byKey(const Key('chip-filters')));
      await tapVisible(
        tester,
        find.descendant(
          of: find.byKey(const Key('switch-same-day')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filters-apply')));
      await tester.pumpAndSettle();
      expect(find.text('No products match'), findsOneWidget);

      await tester.tap(find.byKey(const Key('clear-filters')));
      await tester.pumpAndSettle();
      expect(find.text('Ceramic Coffee Mug Set'), findsOneWidget);
    });

    testWidgets('scrolling loads the next page', (tester) async {
      final repo = FakeStorefrontRepository(products: manyProducts(45));
      await pumpStore(
        tester,
        repo: repo,
        location: '/customer/categories/audio',
      );
      expect(find.text('45 products'), findsOneWidget);
      expect(repo.queries.where((q) => q.categoryId == 'c-audio').last.page, 0);

      await tester.drag(
        find.byKey(const Key('product-list')),
        const Offset(0, -6000),
      );
      await tester.pumpAndSettle();
      final pages = repo.queries
          .where((q) => q.categoryId == 'c-audio' && q.pageSize == 20)
          .map((q) => q.page)
          .toSet();
      expect(pages, containsAll([0, 1]));
    });

    testWidgets('a collection list has its title', (tester) async {
      await pumpStore(tester, location: '/customer/collections/best-sellers');
      expect(find.text('Best sellers'), findsOneWidget);
      expect(find.text('2 products'), findsOneWidget);
    });

    testWidgets('an unknown category says so', (tester) async {
      await pumpStore(tester, location: '/customer/categories/nope');
      expect(find.text("This category isn't available"), findsOneWidget);
    });

    testWidgets('a failed load can be retried', (tester) async {
      final repo = FakeStorefrontRepository()..failBrowse = true;
      await pumpStore(
        tester,
        repo: repo,
        location: '/customer/categories/audio',
      );
      expect(find.text('Try again'), findsOneWidget);
      repo.failBrowse = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('2 products'), findsOneWidget);
    });

    testWidgets('business buyers cannot filter or sort by price', (
      tester,
    ) async {
      final repo = FakeStorefrontRepository(business: true);
      await pumpStore(
        tester,
        repo: repo,
        email: 'sokha@k.example',
        location: '/business/categories/audio',
      );
      expect(find.byKey(const Key('chip-under')), findsNothing);
      expect(find.text('Price on quote'), findsWidgets);

      await tapVisible(tester, find.byKey(const Key('chip-sort')));
      expect(find.text('Price: low to high'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();

      await tapVisible(tester, find.byKey(const Key('chip-filters')));
      expect(find.text('Price'), findsNothing);
      expect(find.byKey(const Key('price-min')), findsNothing);
    });

    testWidgets('a card opens the product', (tester) async {
      final c = await pumpStore(tester, location: '/customer/categories/audio');
      await tester.tap(find.text('Wireless Headphones Pro'));
      await tester.pumpAndSettle();
      expect(_location(c), '/customer/products/p-hp');
    });

    testWidgets('fits the web layout', (tester) async {
      await pumpStore(
        tester,
        size: web,
        repo: FakeStorefrontRepository(products: manyProducts(12)),
        location: '/customer/categories/audio',
      );
      expect(tester.takeException(), isNull);
      // Six columns on a wide screen: the first row is level.
      final first = tester.getTopLeft(find.text('Speaker 0'));
      final sixth = tester.getTopLeft(find.text('Speaker 5'));
      expect(sixth.dy, first.dy);
    });
  });
}
