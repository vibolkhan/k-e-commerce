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
import 'package:k_e_commerce/features/auth/domain/profile.dart';
import 'package:k_e_commerce/features/auth/presentation/auth_providers.dart';
import 'package:k_e_commerce/features/storefront/presentation/search_widgets.dart';
import 'package:k_e_commerce/features/storefront/presentation/store_widgets.dart';

import '../../helpers.dart';
import '../auth/fake_auth_repository.dart';
import 'fakes.dart';

const _sokha = Profile(
  id: 'b',
  role: AppRole.business,
  fullName: 'Sokha Chan',
  email: 'sokha@k.example',
);

typedef SearchHarness = ({
  ProviderContainer container,
  FakeStorefrontRepository store,
  FakeSearchRepository search,
});

/// The whole app opened on C-04 with fake storefront and search data.
Future<SearchHarness> pumpSearch(
  WidgetTester tester, {
  List<FakeProduct>? products,
  List<String> recent = const [],
  bool business = false,
  Size size = const Size(390, 844),
  String? location,
}) async {
  setViewSize(tester, size);
  final auth = FakeAuthRepository(accounts: {'sokha@k.example': _sokha});
  addTearDown(auth.dispose);
  if (business) await auth.signInWithPassword('sokha@k.example', 'password123');
  final store = FakeStorefrontRepository(
    products: products,
    business: business,
  );
  final search = FakeSearchRepository(store, recent: recent);
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        const AppConfig(env: AppEnv.dev, supabaseUrl: '', supabaseAnonKey: ''),
      ),
      onboardedDevice,
      authRepositoryProvider.overrideWithValue(auth),
      clockProvider.overrideWithValue(() => storeNow),
      ...storefrontOverrides(store, search: search),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const KApp()),
  );
  await tester.pumpAndSettle();
  container
      .read(routerProvider)
      .go(location ?? (business ? '/business/search' : '/customer/search'));
  await tester.pumpAndSettle();
  return (container: container, store: store, search: search);
}

final _field = find.descendant(
  of: find.byKey(const Key('search-field')),
  matching: find.byType(TextField),
);

/// Types [text] and waits for the suggestions.
Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(_field, text);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// Types [text] and searches.
Future<void> searchFor(WidgetTester tester, String text) async {
  await type(tester, text);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder rich(String text) => find.textContaining(text, findRichText: true);

String _path(ProviderContainer c) => c.read(routerProvider).state.uri.path;

const _speakers = [
  FakeProduct(
    id: 's1',
    name: 'Party Speaker',
    categoryId: 'c-audio',
    cents: 8900,
    sold: 30,
  ),
  FakeProduct(
    id: 's2',
    name: 'Speaker Mini',
    categoryId: 'c-audio',
    cents: 2900,
    sold: 20,
    available: 0,
  ),
  FakeProduct(
    id: 's3',
    name: 'Smart Speaker',
    categoryId: 'c-audio',
    cents: 5900,
    sold: 10,
  ),
];

void main() {
  group('C-04 typing', () {
    testWidgets(
      'opens ready to type, with recent searches and popular categories',
      (tester) async {
        await pumpSearch(tester, recent: ['rice cooker', 'desk lamp']);
        expect(tester.widget<TextField>(_field).focusNode!.hasFocus, isTrue);
        expect(find.text('Recent searches'), findsOneWidget);
        expect(find.byKey(const Key('recent-rice cooker')), findsOneWidget);
        expect(find.byKey(const Key('recent-desk lamp')), findsOneWidget);
        expect(find.text('Popular categories'), findsOneWidget);
        expect(find.byKey(const Key('popular-audio')), findsOneWidget);
        expect(find.byKey(const Key('popular-kitchen')), findsOneWidget);
      },
    );

    testWidgets('suggests words, a category and products after 2 characters', (
      tester,
    ) async {
      final s = await pumpSearch(tester);
      await type(tester, 'h');
      expect(find.byKey(const Key('suggestion-term-0')), findsNothing);

      await type(tester, 'head');
      expect(s.search.suggested.last, 'head');
      expect(
        find.descendant(
          of: find.byKey(const Key('suggestion-term-0')),
          matching: rich('headphones'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('suggestion-scope')),
          matching: rich('headphones in Audio'),
        ),
        findsOneWidget,
      );
      expect(rich('Wireless Headphones Pro'), findsOneWidget);
      expect(find.text(r'$49.00 · Audio'), findsOneWidget);
      // Recent and popular stay under the suggestions.
      expect(find.text('Popular categories'), findsOneWidget);
    });

    testWidgets('a suggested word searches for it', (tester) async {
      await pumpSearch(tester);
      await type(tester, 'head');
      await tapOn(tester, find.byKey(const Key('suggestion-term-0')));
      expect(rich('1 result for “headphones”'), findsOneWidget);
    });

    testWidgets('a suggested product opens it', (tester) async {
      final s = await pumpSearch(tester);
      await type(tester, 'head');
      await tapOn(tester, find.byKey(const Key('suggestion-product-p-hp')));
      expect(_path(s.container), '/customer/products/p-hp');
    });

    testWidgets('a popular category opens its list', (tester) async {
      final s = await pumpSearch(tester);
      await tapOn(tester, find.byKey(const Key('popular-audio')));
      expect(_path(s.container), '/customer/categories/audio');
    });

    testWidgets('clearing recent searches asks first', (tester) async {
      final s = await pumpSearch(tester, recent: ['lamp']);
      await tapOn(tester, find.byKey(const Key('recent-clear')));
      expect(find.text('Clear recent searches?'), findsOneWidget);
      await tapOn(tester, find.text('Cancel').last);
      expect(find.byKey(const Key('recent-lamp')), findsOneWidget);

      await tapOn(tester, find.byKey(const Key('recent-clear')));
      await tapOn(
        tester,
        find.descendant(
          of: find.byType(KConfirmDialog),
          matching: find.text('Clear'),
        ),
      );
      expect(s.search.recent, isEmpty);
      expect(find.text('Recent searches'), findsNothing);
    });

    testWidgets('Cancel with nothing searched leaves', (tester) async {
      final s = await pumpSearch(tester);
      await tapOn(tester, find.byKey(const Key('search-cancel')));
      expect(_path(s.container), '/customer');
    });
  });

  group('C-04a results', () {
    testWidgets('a search lists results with prices, timed and recorded', (
      tester,
    ) async {
      final s = await pumpSearch(tester);
      await searchFor(tester, 'Headphones');
      expect(rich('1 result for “Headphones”'), findsOneWidget);
      expect(find.byType(SearchResultRow), findsOneWidget);
      expect(find.text('Wireless Headphones Pro'), findsOneWidget);
      expect(find.text(r'$49.00'), findsOneWidget);
      expect(find.text('≈ KHR 200,900'), findsOneWidget);
      expect(find.text('Sort: Best match'), findsOneWidget);
      expect(s.store.queries.last.search, 'Headphones');

      final record = s.search.recorded.single;
      expect(record.query, 'Headphones');
      expect(record.results, 1);
      expect(record.took, lessThan(const Duration(seconds: 1)));

      // It is now a recent search.
      await tapOn(tester, _field);
      expect(find.byKey(const Key('recent-headphones')), findsOneWidget);
    });

    testWidgets('Khmer queries return results', (tester) async {
      await pumpSearch(tester);
      await searchFor(tester, 'កាស');
      expect(rich('1 result'), findsOneWidget);
      expect(find.text('Wireless Headphones Pro'), findsOneWidget);
    });

    testWidgets('a link with ?q= opens on its results', (tester) async {
      final s = await pumpSearch(tester, location: '/customer/search?q=mug');
      expect(find.text('Ceramic Coffee Mug Set'), findsOneWidget);
      expect(s.search.recorded.single.query, 'mug');
    });

    testWidgets('In stock and the sort sheet with Best match', (tester) async {
      final s = await pumpSearch(tester, products: _speakers);
      await searchFor(tester, 'speaker');
      expect(rich('3 results'), findsOneWidget);

      await tapOn(tester, find.byKey(const Key('chip-in-stock')));
      expect(rich('2 results'), findsOneWidget);
      expect(find.text('Speaker Mini'), findsNothing);
      expect(s.store.queries.last.search, 'speaker');

      await tapOn(tester, find.byKey(const Key('chip-sort')));
      expect(find.byKey(const Key('sort-relevance')), findsOneWidget);
      await tapOn(tester, find.byKey(const Key('sort-price_asc')));
      await tapOn(tester, find.byKey(const Key('sort-apply')));
      expect(find.text('Sort: Price: low to high'), findsOneWidget);
      final names = tester
          .widgetList<SearchResultRow>(find.byType(SearchResultRow))
          .map((r) => r.item.name.en);
      expect(names, ['Smart Speaker', 'Party Speaker']);
      // Sorting is not a new search.
      expect(s.search.recorded, hasLength(1));
    });

    testWidgets('filters that leave nothing offer to clear them', (
      tester,
    ) async {
      await pumpSearch(tester, products: [_speakers[1]]);
      await searchFor(tester, 'speaker');
      await tapOn(tester, find.byKey(const Key('chip-in-stock')));
      expect(find.text('No products match'), findsOneWidget);
      expect(find.byKey(const Key('did-you-mean')), findsNothing);
      await tapOn(tester, find.byKey(const Key('clear-filters')));
      expect(rich('1 result'), findsOneWidget);
    });

    testWidgets('"headphones in Audio" narrows the search to the category', (
      tester,
    ) async {
      final s = await pumpSearch(tester);
      await type(tester, 'head');
      await tapOn(tester, find.byKey(const Key('suggestion-scope')));
      expect(rich('1 result for “headphones” in Audio'), findsOneWidget);
      expect(s.store.queries.last.categoryId, 'c-audio');

      await tapOn(tester, find.byKey(const Key('chip-scope')));
      expect(s.store.queries.last.categoryId, isNull);
      expect(find.byKey(const Key('chip-scope')), findsNothing);
    });

    testWidgets('more results load on request', (tester) async {
      await pumpSearch(tester, products: manyProducts(25));
      await searchFor(tester, 'speaker');
      expect(rich('25 results'), findsOneWidget);
      expect(
        find.byType(SearchResultRow, skipOffstage: false),
        findsNWidgets(20),
      );
      await tester.scrollUntilVisible(
        find.text('Show 5 more results'),
        400,
        scrollable: find.descendant(
          of: find.byKey(const Key('search-results')),
          matching: find.byType(Scrollable),
        ),
      );
      await tapOn(tester, find.text('Show 5 more results'));
      expect(
        find.byType(SearchResultRow, skipOffstage: false),
        findsNWidgets(25),
      );
      expect(find.byKey(const Key('show-more')), findsNothing);
    });

    testWidgets('editing a search and cancelling returns to the results', (
      tester,
    ) async {
      final s = await pumpSearch(tester);
      await searchFor(tester, 'mug');
      await tapOn(tester, _field);
      expect(find.byKey(const Key('search-cancel')), findsOneWidget);
      await type(tester, 'mugs and more');
      await tapOn(tester, find.byKey(const Key('search-cancel')));
      expect(find.byKey(const Key('result-count')), findsOneWidget);
      expect(tester.widget<TextField>(_field).controller!.text, 'mug');

      await tapOn(tester, find.byKey(const Key('search-back')));
      expect(_path(s.container), '/customer');
    });

    testWidgets('a failed search can be retried', (tester) async {
      final s = await pumpSearch(tester);
      s.store.failBrowse = true;
      await searchFor(tester, 'mug');
      expect(find.text('Try again'), findsOneWidget);
      s.store.failBrowse = false;
      await tapOn(tester, find.text('Try again'));
      expect(find.text('Ceramic Coffee Mug Set'), findsOneWidget);
    });

    testWidgets('business buyers search without prices', (tester) async {
      await pumpSearch(tester, business: true);
      await type(tester, 'head');
      expect(find.text('Audio'), findsWidgets); // the category, no price
      expect(rich(r'$'), findsNothing);

      await searchFor(tester, 'headphones');
      expect(find.text('Price on quote'), findsOneWidget);
      expect(find.text('Min. 5'), findsOneWidget);
      expect(rich(r'$'), findsNothing);
      await tapOn(tester, find.byKey(const Key('chip-sort')));
      expect(find.byKey(const Key('sort-price_asc')), findsNothing);
    });

    testWidgets('wide screens show the product grid', (tester) async {
      await pumpSearch(
        tester,
        products: _speakers,
        size: const Size(1280, 900),
      );
      await searchFor(tester, 'speaker');
      expect(find.byType(StoreProductCard), findsNWidgets(3));
      expect(find.byType(SearchResultRow), findsNothing);
    });
  });

  group('C-04b no results', () {
    testWidgets('"hedfones" suggests headphones', (tester) async {
      final s = await pumpSearch(tester);
      await type(tester, 'hedfones');
      // While typing: the corrected word.
      expect(
        find.descendant(
          of: find.byKey(const Key('suggestion-term-0')),
          matching: rich('headphones'),
        ),
        findsOneWidget,
      );

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('No results for “hedfones”'), findsOneWidget);
      expect(find.text('Did you mean '), findsOneWidget);
      expect(find.byKey(const Key('did-you-mean')), findsOneWidget);
      expect(find.text('Try this'), findsOneWidget);
      expect(find.text('Check the spelling'), findsOneWidget);
      expect(find.byKey(const Key('popular-audio')), findsOneWidget);
      expect(s.search.recorded.single.results, 0);

      await tapOn(tester, find.byKey(const Key('did-you-mean')));
      expect(rich('1 result for “headphones”'), findsOneWidget);
      expect(tester.widget<TextField>(_field).controller!.text, 'headphones');
    });

    testWidgets('no suggestion when nothing is close', (tester) async {
      await pumpSearch(tester);
      await searchFor(tester, 'zzzzqq');
      expect(find.text('No results for “zzzzqq”'), findsOneWidget);
      expect(find.byKey(const Key('did-you-mean')), findsNothing);
      expect(find.text('Try this'), findsOneWidget);
    });
  });
}
