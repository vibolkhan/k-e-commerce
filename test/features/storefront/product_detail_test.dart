import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/features/catalog/domain/product_draft.dart';
import 'package:k_e_commerce/features/storefront/domain/product_detail.dart';
import 'package:k_e_commerce/features/storefront/domain/reviews.dart';

import 'product_detail_fixtures.dart';

void main() {
  group('ProductDetail.fromJson', () {
    test('reads variants with price and stock, specs and related', () {
      final p = detailFrom(headphonesJson());
      expect(p.name.en, 'Wireless Headphones Pro');
      expect(p.variants.map((v) => v.sku), [
        'HP-PRO-BLK',
        'HP-PRO-WHT',
        'HP-PRO-SKY',
      ]);
      expect(p.variants.first.priceCents, 4900);
      expect(p.variants.first.stock, isA<LowStock>());
      expect((p.variants.first.stock as LowStock).left, 11);
      expect(p.variants[1].stock, isA<InStock>());
      expect(p.variants[2].stock, isA<OutOfStock>());
      expect(p.maxPerOrder, 5);
      expect(p.specs.first, const Spec(name: 'Model', value: 'WH-PRO'));
      expect(p.highlights, hasLength(2));
      expect(p.related.map((r) => r.id), ['p-spk', 'p-watch']);
      expect(p.related.first.priceCents, 2900);
      expect(p.freeDeliveryCents, 5000);
      expect(p.soldOut, isFalse);
    });

    test('business buyers get no prices', () {
      final p = detailFrom(headphonesJson(business: true));
      expect(p.variants.every((v) => v.priceCents == null), isTrue);
      expect(p.related.every((r) => r.priceCents == null), isTrue);
    });

    test('images become URLs and keep their colour link', () {
      final p = detailFrom(
        headphonesJson(
          images: [
            {
              'path': 'hp/1.jpg',
              'alt': {'en': 'Front'},
              'sort': 0,
            },
            {'path': 'hp/2.jpg', 'sort': 1, 'variant_id': 'v-wht'},
          ],
        ),
      );
      expect(p.images.first.url, 'https://img.test/hp/1.jpg');
      expect(p.images.first.alt.en, 'Front');
      expect(p.imageIndexFor(p.variants[1]), 1);
      expect(p.imageIndexFor(p.variants[0]), isNull);
    });
  });

  group('options', () {
    test('axes list each attribute with its values in order', () {
      final tee = detailFrom(teeJson());
      expect(tee.axes.map((a) => a.key), ['colour', 'size']);
      expect(tee.axes.first.values, ['White', 'Navy']);
      expect(tee.axes.first.isColour, isTrue);
      expect(tee.valuesOf('size'), ['M', 'L']);
    });

    test('a single variant has nothing to choose', () {
      final json = headphonesJson();
      json['variants'] = [(json['variants'] as List).first];
      expect(detailFrom(json).axes, isEmpty);
    });
  });

  group('VariantSelection', () {
    test('starts on the first variant that can be ordered', () {
      final json = headphonesJson();
      (json['variants'] as List).first['available'] = 0;
      final s = VariantSelection.initial(detailFrom(json));
      expect(s.variant!.sku, 'HP-PRO-WHT');
    });

    test('changing colour changes price and stock', () {
      final p = detailFrom(headphonesJson(whitePrice: 5200));
      var s = VariantSelection.initial(p);
      expect(s.variant!.priceCents, 4900);
      expect(s.variant!.stock, isA<LowStock>());
      s = s.select('colour', 'White');
      expect(s.variant!.priceCents, 5200);
      expect(s.variant!.stock, isA<InStock>());
    });

    test('out-of-stock values are disabled', () {
      final s = VariantSelection.initial(detailFrom(headphonesJson()));
      expect(s.isEnabled('colour', 'Black'), isTrue);
      expect(s.isEnabled('colour', 'White'), isTrue);
      expect(s.isEnabled('colour', 'Sky'), isFalse);
    });

    test('disabled values follow the other choices', () {
      var s = VariantSelection.initial(detailFrom(teeJson()));
      expect(s.variant!.sku, 'TEE-W-M');
      // White comes in M only; Navy comes in L only.
      expect(s.isEnabled('size', 'L'), isFalse);
      expect(s.isEnabled('colour', 'Navy'), isFalse);
      s = s.select('size', 'L'); // White L is sold out: stays a valid combo
      expect(s.variant!.sku, 'TEE-W-L');
      expect(s.isEnabled('colour', 'Navy'), isTrue);
    });

    test('a value that does not combine moves the other choices', () {
      final json = teeJson();
      (json['variants'] as List).removeWhere((v) => v['id'] == 't-nm');
      var s = VariantSelection.initial(detailFrom(json));
      s = s.select('colour', 'Navy'); // no Navy M: moves to Navy L
      expect(s.variant!.sku, 'TEE-N-L');
      expect(s.valueOf('size'), 'L');
    });

    test('max quantity is the per-order limit, stock and line cap', () {
      final p = detailFrom(headphonesJson());
      var s = VariantSelection.initial(p);
      expect(s.maxQty, 5); // limit 5, 11 in stock
      final low = headphonesJson();
      (low['variants'] as List).first['available'] = 3;
      expect(VariantSelection.initial(detailFrom(low)).maxQty, 3);
      s = VariantSelection.initial(detailFrom(teeJson()));
      expect(s.maxQty, 3); // no limit, 3 in stock
      final lots = teeJson();
      (lots['variants'] as List).first['available'] = 5000;
      expect(
        VariantSelection.initial(detailFrom(lots)).maxQty,
        ProductDetail.cartLineMax,
      );
    });

    test('nothing can be added when it is sold out', () {
      final json = headphonesJson();
      for (final v in json['variants'] as List) {
        v['available'] = 0;
      }
      final p = detailFrom(json);
      expect(p.soldOut, isTrue);
      expect(VariantSelection.initial(p).maxQty, 0);
    });
  });

  group('specs', () {
    test('reads the F09 array shape in order', () {
      expect(
        specRowsFrom([
          {'name': 'Battery', 'value': 'Up to 30 h'},
          {'name': ' ', 'value': 'dropped'},
          {'name': 'Weight', 'value': 250},
        ]),
        const [
          Spec(name: 'Battery', value: 'Up to 30 h'),
          Spec(name: 'Weight', value: '250'),
        ],
      );
    });

    test('reads the older object shape with readable labels', () {
      expect(specRowsFrom({'model': 'WH-PRO', 'warranty_months': 12}), const [
        Spec(name: 'Model', value: 'WH-PRO'),
        Spec(name: 'Warranty months', value: '12'),
      ]);
      expect(specRowsFrom(null), isEmpty);
      expect(specRowsFrom('nonsense'), isEmpty);
    });
  });

  test('colour swatches know the catalogue colours', () {
    expect(colourSwatch('Black'), 0xFF1E293B);
    expect(colourSwatch(' sky '), 0xFF7DD3FC);
    expect(colourSwatch('Ultraviolet'), 0xFF94A3B8);
  });

  test('variant labels join attributes', () {
    final tee = detailFrom(teeJson());
    expect(tee.variants.first.label, 'White · M');
  });

  test('review summaries give bar shares and initials', () {
    const r = ProductReviews(total: 4, byStars: {5: 3, 1: 1});
    expect(r.shareOf(5), 0.75);
    expect(r.shareOf(3), 0);
    expect(ProductReviews.none.isEmpty, isTrue);
    expect(ProductReviews.none.shareOf(5), 0);
    final review = Review(
      id: 'r',
      author: 'Sreymom K.',
      rating: 5,
      createdAt: DateTime.utc(2026, 10, 18),
    );
    expect(review.initials, 'SK');
  });
}
