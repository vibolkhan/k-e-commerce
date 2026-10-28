import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/core/time/cutoff.dart';
import 'package:k_e_commerce/features/storefront/domain/browse.dart';
import 'package:k_e_commerce/features/storefront/domain/storefront.dart';
import 'package:k_e_commerce/features/storefront/presentation/store_widgets.dart';

import 'fakes.dart';

/// Phnom Penh wall-clock [hour]:[minute] on [day] October 2026, as an
/// instant.
DateTime pp(int day, int hour, [int minute = 0, int month = 10]) =>
    DateTime.utc(
      2026,
      month,
      day,
      hour,
      minute,
    ).subtract(const Duration(hours: 7));

StoreClock clockAt(DateTime now, {Set<String> holidays = const {}}) =>
    StoreClock(
      serverNow: now,
      cutoff: Cutoff.standard,
      holidays: holidays,
      fetchedAt: now,
    );

void main() {
  group('BrowseQuery', () {
    test('any change goes back to the first page', () {
      const q = BrowseQuery(categoryId: 'c', page: 3);
      expect(q.copyWith(inStock: true).page, 0);
      expect(q.copyWith(sort: BrowseSort.newest).page, 0);
      expect(q.atPage(2).offset, 40);
    });

    test('the Filters chip counts each kind of filter once', () {
      const q = BrowseQuery();
      expect(q.activeFilterCount, 0);
      expect(
        q
            .copyWith(
              brands: {'Sonora', 'Nimbus'},
              minCents: () => 100,
              maxCents: () => 5000,
              minRating: () => 4,
              inStock: true,
              sameDay: true,
            )
            .activeFilterCount,
        5,
      );
    });

    test('nullable fields can be cleared', () {
      final q = const BrowseQuery().copyWith(maxCents: () => 5000);
      expect(q.isUnderChipOn, isTrue);
      expect(q.copyWith(maxCents: () => null).maxCents, isNull);
      expect(q.copyWith(inStock: true).maxCents, 5000);
    });

    test('cleared keeps the category and sort, drops the filters', () {
      final q = const BrowseQuery(
        categoryId: 'c',
        sort: BrowseSort.newest,
      ).copyWith(inStock: true, brands: {'Sonora'});
      final c = q.cleared();
      expect(c.categoryId, 'c');
      expect(c.sort, BrowseSort.newest);
      expect(c.activeFilterCount, 0);
    });

    test('business buyers lose price filters and price sorts', () {
      final q = const BrowseQuery()
          .copyWith(
            minCents: () => 100,
            maxCents: () => 5000,
            sort: BrowseSort.priceAsc,
            inStock: true,
          )
          .forBusiness();
      expect(q.minCents, isNull);
      expect(q.maxCents, isNull);
      expect(q.sort, BrowseSort.popular);
      expect(q.inStock, isTrue);
      expect(
        BrowseSort.options(business: true),
        isNot(contains(BrowseSort.priceAsc)),
      );
      expect(BrowseSort.options(business: false), hasLength(5));
    });

    test('RPC params', () {
      final p = const BrowseQuery(
        collection: 'best-sellers',
      ).copyWith(brands: {'b', 'a'}).atPage(1).toRpcParams();
      expect(p['p_collection'], 'best-sellers');
      expect(p['p_brands'], ['a', 'b']);
      expect(p['p_offset'], 20);
      expect(p['p_sort'], 'popular');
    });

    test('equality ignores brand order', () {
      expect(
        const BrowseQuery().copyWith(brands: {'a', 'b'}),
        const BrowseQuery().copyWith(brands: {'b', 'a'}),
      );
    });
  });

  group('BrowsePage', () {
    test('reads catalog_browse JSON', () {
      final page = BrowsePage.fromJson({
        'rows': [
          {
            'id': 'p1',
            'slug': 'x',
            'name': {'en': 'X', 'km': 'អ'},
            'brand': 'Sonora',
            'rating_avg': 4.6,
            'rating_count': 128,
            'same_day': true,
            'tags': ['New'],
            'min_price_cents': 4900,
            'available': 0,
            'main_image': 'products/p1/a.jpg',
          },
        ],
        'total': 7,
        'brands': [
          {'brand': 'Sonora', 'count': 3},
        ],
        'price_bounds': {'min': 800, 'max': 7900},
        'all_same_day': true,
      }, imageUrl: (p) => 'https://cdn/$p');
      final item = page.items.single;
      expect(item.priceCents, 4900);
      expect(item.soldOut, isTrue);
      expect(item.imageUrl, 'https://cdn/products/p1/a.jpg');
      expect(item.name.of('km'), 'អ');
      expect(page.total, 7);
      expect(page.brands.single.count, 3);
      expect(page.maxPriceCents, 7900);
      expect(page.allSameDay, isTrue);
    });

    test('business rows have no price and no bounds', () {
      final page = BrowsePage.fromJson({
        'rows': [
          {
            'id': 'p1',
            'name': {'en': 'X'},
            'min_price_cents': null,
          },
        ],
        'total': 1,
        'price_bounds': null,
      }, imageUrl: (p) => p);
      expect(page.items.single.priceCents, isNull);
      expect(page.items.single.imageUrl, isNull);
      expect(page.minPriceCents, isNull);
    });
  });

  group('SameDayStatus', () {
    test('before the cut-off: time left for today', () {
      final now = pp(27, 10, 25);
      final s = SameDayStatus.at(now, clockAt(now));
      expect(s, isA<SameDayOpen>());
      expect(
        (s as SameDayOpen).remaining,
        const Duration(hours: 4, minutes: 35),
      );
    });

    test('at exactly 3:00 PM the cut-off has passed', () {
      final now = pp(27, 15);
      final s = SameDayStatus.at(now, clockAt(now));
      expect(s, isA<SameDayClosed>());
      expect((s as SameDayClosed).isTomorrow, isTrue);
      expect(s.nextDay, DateTime.utc(2026, 10, 28));
    });

    test('just after midnight Phnom Penh is a new day', () {
      // 17:30 UTC is 00:30 the next day in Phnom Penh.
      final now = DateTime.utc(2026, 10, 27, 17, 30);
      expect(SameDayStatus.at(now, clockAt(now)), isA<SameDayOpen>());
    });

    test('holidays are skipped', () {
      final eve = pp(8, 16, 0, 11);
      final s = SameDayStatus.at(eve, clockAt(eve, holidays: {'2026-11-09'}));
      expect((s as SameDayClosed).nextDay, DateTime.utc(2026, 11, 10));
      expect(s.isTomorrow, isFalse);

      final onHoliday = pp(9, 9, 0, 11);
      expect(
        SameDayStatus.at(
          onHoliday,
          clockAt(onHoliday, holidays: {'2026-11-09'}),
        ),
        isA<SameDayClosed>(),
      );
    });

    test('the store clock follows the server, not the device', () {
      final clock = StoreClock(
        serverNow: pp(27, 14, 50),
        cutoff: Cutoff.standard,
        fetchedAt: DateTime.utc(2026, 10, 27, 9), // device is 1h10m fast
      );
      final later = clock.nowFrom(DateTime.utc(2026, 10, 27, 9, 5));
      expect(
        (SameDayStatus.at(later, clock) as SameDayOpen).remaining,
        const Duration(minutes: 5),
      );
    });

    test('reads storefront_clock JSON', () {
      final fetched = DateTime.utc(2026, 10, 27, 3);
      final c = StoreClock.fromJson({
        'now': '2026-10-27T03:25:00+00:00',
        'cutoff': '14:30',
        'holidays': ['2026-11-09'],
      }, fetched);
      expect(c.cutoff.hour, 14);
      expect(c.cutoff.minute, 30);
      expect(c.holidays, {'2026-11-09'});
      expect(c.nowFrom(fetched), DateTime.utc(2026, 10, 27, 3, 25));
    });
  });

  group('home content', () {
    test('banner paths drop the bucket prefix', () {
      expect(bannerStoragePath('banners/same-day.png'), 'same-day.png');
      expect(bannerStoragePath('promo/a.png'), 'promo/a.png');
      expect(bannerStoragePath(''), isNull);
      expect(bannerStoragePath(null), isNull);
    });

    test('banner rows', () {
      final b = HomeBanner.fromRow({
        'id': 'b1',
        'title': {'en': 'Order by 3 PM, get it today'},
        'badge': {'en': 'Same-day delivery'},
        'image_path': 'banners/truck.png',
        'link_type': 'collection',
        'link_target': 'best-sellers',
      }, imageUrl: (p) => 'cdn/$p');
      expect(b.imageUrl, 'cdn/truck.png');
      expect(b.linkType, BannerLinkType.collection);
      expect(b.subtitle.isEmpty, isTrue);
    });

    test('audiences', () {
      expect(Audience.retail.visible, ['all', 'retail']);
      expect(Audience.business.visible, ['all', 'business']);
      expect(
        HomeCollections.featured(Audience.business),
        'popular-for-offices',
      );
      expect(HomeCollections.featured(Audience.retail), 'best-sellers');
    });

    test('category tree and home shortcuts', () {
      final tree = CategoryTree(storeCategories);
      expect(tree.top.map((c) => c.slug), ['electronics', 'kitchen', 'pantry']);
      expect(tree.childrenOf('c-elec').single.slug, 'audio');
      expect(tree.shortcuts(4).map((c) => c.slug), [
        'electronics',
        'kitchen',
        'pantry',
        'audio',
      ]);
      expect(tree.bySlug('audio')?.id, 'c-audio');
      expect(tree.bySlug('nope'), isNull);
    });

    test('product grid columns by width', () {
      expect(StoreProductGrid.columnsFor(358), 2);
      expect(StoreProductGrid.columnsFor(800), 4);
      expect(StoreProductGrid.columnsFor(1168), 6);
    });
  });
}
