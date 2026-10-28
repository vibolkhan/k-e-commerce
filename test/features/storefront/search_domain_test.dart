import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/core/router/app_routes.dart';
import 'package:k_e_commerce/features/storefront/data/recent_search_store.dart';
import 'package:k_e_commerce/features/storefront/domain/browse.dart';
import 'package:k_e_commerce/features/storefront/domain/search.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('queries', () {
    test('are normalised the way the server keeps them', () {
      expect(
        normalizeSearch('  Wireless   HEADphones '),
        'wireless headphones',
      );
      expect(normalizeSearch('កាស'), 'កាស');
      expect(normalizeSearch('x' * 120).length, 100);
    });

    test('a search travels with the browse query', () {
      const q = BrowseQuery(search: 'headphones', sort: BrowseSort.relevance);
      expect(q.toRpcParams()['p_q'], 'headphones');
      expect(q.toRpcParams()['p_sort'], 'relevance');
      expect(q.copyWith(inStock: true).search, 'headphones');
      expect(q.atPage(2).search, 'headphones');
      expect(q.cleared().search, 'headphones');
      expect(q.forBusiness().search, 'headphones');
      expect(
        q,
        isNot(const BrowseQuery(search: 'speaker', sort: BrowseSort.relevance)),
      );
      expect(const BrowseQuery().toRpcParams()['p_q'], isNull);
    });

    test('Best match is offered first, and only for search results', () {
      expect(
        BrowseSort.options(business: false, search: true).first,
        BrowseSort.relevance,
      );
      expect(
        BrowseSort.options(business: false),
        isNot(contains(BrowseSort.relevance)),
      );
      expect(BrowseSort.options(business: true, search: true), [
        BrowseSort.relevance,
        BrowseSort.popular,
        BrowseSort.newest,
        BrowseSort.rating,
      ]);
    });

    test('the route carries the query', () {
      expect(AppRoutes.search('/customer'), '/customer/search');
      expect(
        AppRoutes.search('/customer', query: 'rice cooker'),
        '/customer/search?q=rice+cooker',
      );
    });
  });

  group('recent searches', () {
    test('newest first, once each, at most eight', () {
      var recent = <String>[];
      for (final q in ['lamp', 'Mug', 'lamp ', 'bottle']) {
        recent = pushRecent(recent, q);
      }
      expect(recent, ['bottle', 'lamp', 'mug']);
      for (var i = 0; i < 10; i++) {
        recent = pushRecent(recent, 'item $i');
      }
      expect(recent, hasLength(recentSearchLimit));
      expect(recent.first, 'item 9');
      expect(pushRecent(recent, '   '), same(recent));
    });

    test('a guest keeps them on the device', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPrefsRecentSearchStore(
        await SharedPreferences.getInstance(),
      );
      await store.push('Desk lamp');
      await store.push('mug');
      expect(store.read(), ['mug', 'desk lamp']);
      final again = SharedPrefsRecentSearchStore(
        await SharedPreferences.getInstance(),
      );
      expect(again.read(), ['mug', 'desk lamp']);
      await store.clear();
      expect(store.read(), isEmpty);
    });
  });

  group('suggestions', () {
    test('runs split around the typed text, any case', () {
      expect(matchRuns('Wireless Headphones Pro', 'head'), [
        (text: 'Wireless ', match: false),
        (text: 'Head', match: true),
        (text: 'phones Pro', match: false),
      ]);
      expect(matchRuns('headphones', 'head'), [
        (text: 'head', match: true),
        (text: 'phones', match: false),
      ]);
      expect(matchRuns('headphones', 'hedf'), [
        (text: 'headphones', match: false),
      ]);
      expect(matchRuns('កាសឥតខ្សែ Pro', 'កាស').first, (
        text: 'កាស',
        match: true,
      ));
    });

    test('are read from catalog_suggest', () {
      final s = SearchSuggestions.fromJson({
        'terms': [
          {'term': 'headphones', 'fuzzy': true},
        ],
        'scope': {
          'term': 'headphones',
          'category': {
            'id': 'c1',
            'slug': 'audio',
            'name': {'en': 'Audio', 'km': 'សំឡេង'},
          },
        },
        'products': [
          {
            'id': 'p1',
            'name': {'en': 'Wireless Headphones Pro'},
            'brand': 'Sonora',
            'min_price_cents': 4900,
            'category': {'en': 'Audio'},
            'main_image': 'p1/a.jpg',
          },
          {
            'id': 'p2',
            'name': {'en': 'Kids Headphones'},
            'min_price_cents': null,
            'category': null,
            'main_image': null,
          },
        ],
      }, imageUrl: (path) => 'https://img/$path');
      expect(s.terms.single.term, 'headphones');
      expect(s.terms.single.fuzzy, isTrue);
      expect(s.scope!.category.slug, 'audio');
      expect(s.scope!.category.name.km, 'សំឡេង');
      expect(s.products.first.priceCents, 4900);
      expect(s.products.first.imageUrl, 'https://img/p1/a.jpg');
      expect(s.products.last.priceCents, isNull); // business buyers
      expect(s.products.last.imageUrl, isNull);
      expect(s.isEmpty, isFalse);
      expect(
        SearchSuggestions.fromJson({'scope': null}, imageUrl: (p) => p).isEmpty,
        isTrue,
      );
    });
  });
}
