import 'package:k_e_commerce/features/storefront/data/product_detail_repository.dart';
import 'package:k_e_commerce/features/storefront/domain/product_detail.dart';
import 'package:k_e_commerce/features/storefront/domain/reviews.dart';

/// `product_detail` for the design's Wireless Headphones Pro (C-05): Black
/// low on stock, White plenty, Sky sold out, 5 per order.
Map<String, dynamic> headphonesJson({
  bool business = false,
  List<Map<String, dynamic>> images = const [],
  int whitePrice = 4900,
}) => {
  'id': 'p-hp',
  'slug': 'wireless-headphones-pro',
  'name': {'en': 'Wireless Headphones Pro', 'km': 'កាសឥតខ្សែ Pro'},
  'description': {
    'en':
        'Quiet, comfortable over-ear headphones for commuting and calls. '
        'Soft memory-foam cushions, a folding design and a battery that lasts '
        'the whole week.',
  },
  'brand': 'Sonora',
  'category_id': 'c-audio',
  'specs': [
    {'name': 'Model', 'value': 'WH-PRO'},
    {'name': 'Connectivity', 'value': 'Bluetooth 5.3, multipoint'},
    {'name': 'Weight', 'value': '250 g'},
  ],
  'highlights': [
    {'en': 'Active noise cancelling with transparency mode'},
    {'en': 'Up to 30 hours of battery life'},
  ],
  'max_per_order': 5,
  'same_day': true,
  'rfq_enabled': true,
  'rfq_min_qty': 5,
  'rating_avg': 4.6,
  'rating_count': 128,
  'sold_count': 840,
  'images': images,
  'variants': [
    {
      'id': 'v-blk',
      'sku': 'HP-PRO-BLK',
      'attributes': {'colour': 'Black'},
      'sort': 1,
      'price_cents': business ? null : 4900,
      'available': 11,
      'low_stock': true,
    },
    {
      'id': 'v-wht',
      'sku': 'HP-PRO-WHT',
      'attributes': {'colour': 'White'},
      'sort': 2,
      'price_cents': business ? null : whitePrice,
      'available': 40,
      'low_stock': false,
    },
    {
      'id': 'v-sky',
      'sku': 'HP-PRO-SKY',
      'attributes': {'colour': 'Sky'},
      'sort': 3,
      'price_cents': business ? null : 4900,
      'available': 0,
      'low_stock': false,
    },
  ],
  'related': [
    {
      'id': 'p-spk',
      'slug': 'bluetooth-speaker-mini',
      'name': {'en': 'Bluetooth Speaker Mini'},
      'min_price_cents': business ? null : 2900,
      'available': 0,
      'rating_avg': 4.5,
      'rating_count': 77,
    },
    {
      'id': 'p-watch',
      'slug': 'smart-watch-active-2',
      'name': {'en': 'Smart Watch Active 2'},
      'min_price_cents': business ? null : 7900,
      'available': 20,
    },
  ],
  'free_delivery_cents': 5000,
};

/// A tee in colours and sizes: White in M and L, Navy only in M (sold out).
Map<String, dynamic> teeJson() => {
  'id': 'p-tee',
  'slug': 'cotton-crew-tshirt',
  'name': {'en': 'Cotton Crew T-Shirt'},
  'specs': {'fabric_weight_g': 180},
  'max_per_order': null,
  'variants': [
    {
      'id': 't-wm',
      'sku': 'TEE-W-M',
      'attributes': {'colour': 'White', 'size': 'M'},
      'price_cents': 900,
      'available': 3,
    },
    {
      'id': 't-wl',
      'sku': 'TEE-W-L',
      'attributes': {'colour': 'White', 'size': 'L'},
      'price_cents': 1000,
      'available': 0,
    },
    {
      'id': 't-nm',
      'sku': 'TEE-N-M',
      'attributes': {'colour': 'Navy', 'size': 'M'},
      'price_cents': 900,
      'available': 0,
    },
    {
      'id': 't-nl',
      'sku': 'TEE-N-L',
      'attributes': {'colour': 'Navy', 'size': 'L'},
      'price_cents': 1000,
      'available': 7,
    },
  ],
};

ProductDetail detailFrom(Map<String, dynamic> json) =>
    ProductDetail.fromJson(json, imageUrl: (p) => 'https://img.test/$p');

/// Serves fixed product pages by id; counts reads.
class FakeProductDetailRepository implements ProductDetailRepository {
  FakeProductDetailRepository(this.products, {this.fail = false});

  final Map<String, ProductDetail> products;
  bool fail;
  int reads = 0;

  @override
  Future<ProductDetail?> detail(String id) async {
    reads++;
    if (fail) throw Exception('offline');
    return products[id];
  }
}

class FakeReviewsRepository implements ReviewsRepository {
  const FakeReviewsRepository(this.result);
  final ProductReviews result;

  @override
  Future<ProductReviews> reviews(String productId) async => result;
}
