import 'dart:math' as math;

import '../../catalog/domain/i18n_text.dart';
import '../../catalog/domain/product_draft.dart' show Spec;
import 'browse.dart';

/// The product page (C-05): `product_detail`, read under the viewer's RLS.
/// Business buyers can't read prices, so variants carry none for them.
class ProductDetail {
  const ProductDetail({
    required this.id,
    required this.slug,
    required this.name,
    this.description = const I18nText(),
    this.brand,
    this.categoryId,
    this.specs = const [],
    this.highlights = const [],
    this.maxPerOrder,
    this.sameDay = true,
    this.rfqEnabled = false,
    this.rfqMinQty,
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.soldCount = 0,
    this.images = const [],
    this.variants = const [],
    this.related = const [],
    this.freeDeliveryCents,
  });

  factory ProductDetail.fromJson(
    Map<String, dynamic> json, {
    required String Function(String path) imageUrl,
  }) => ProductDetail(
    id: json['id'] as String,
    slug: json['slug'] as String? ?? '',
    name: I18nText.fromJson(json['name']),
    description: I18nText.fromJson(json['description']),
    brand: json['brand'] as String?,
    categoryId: json['category_id'] as String?,
    specs: specRowsFrom(json['specs']),
    highlights: [
      for (final h in json['highlights'] as List? ?? const [])
        if (!I18nText.fromJson(h).isEmpty) I18nText.fromJson(h),
    ],
    maxPerOrder: (json['max_per_order'] as num?)?.toInt(),
    sameDay: json['same_day'] != false,
    rfqEnabled: json['rfq_enabled'] == true,
    rfqMinQty: (json['rfq_min_qty'] as num?)?.toInt(),
    ratingAvg: (json['rating_avg'] as num?)?.toDouble() ?? 0,
    ratingCount: (json['rating_count'] as num?)?.toInt() ?? 0,
    soldCount: (json['sold_count'] as num?)?.toInt() ?? 0,
    images: [
      for (final i
          in (json['images'] as List? ?? const []).cast<Map<String, dynamic>>())
        ProductImage(
          url: imageUrl(i['path'] as String),
          alt: I18nText.fromJson(i['alt']),
          variantId: i['variant_id'] as String?,
        ),
    ],
    variants: [
      for (final v
          in (json['variants'] as List? ?? const [])
              .cast<Map<String, dynamic>>())
        DetailVariant(
          id: v['id'] as String,
          sku: v['sku'] as String? ?? '',
          attributes: {
            for (final e in (v['attributes'] as Map? ?? const {}).entries)
              e.key.toString(): e.value.toString(),
          },
          priceCents: (v['price_cents'] as num?)?.toInt(),
          compareAtCents: (v['compare_at_cents'] as num?)?.toInt(),
          available: math.max((v['available'] as num?)?.toInt() ?? 0, 0),
          lowStock: v['low_stock'] == true,
        ),
    ],
    related: [
      for (final r in json['related'] as List? ?? const [])
        BrowseItem.fromRow(r as Map<String, dynamic>, imageUrl: imageUrl),
    ],
    freeDeliveryCents: (json['free_delivery_cents'] as num?)?.toInt(),
  );

  /// Cart lines are capped at 999 (`cart_items`); a product's own limit is
  /// usually lower.
  static const cartLineMax = 999;

  final String id;
  final String slug;
  final I18nText name;
  final I18nText description;
  final String? brand;
  final String? categoryId;
  final List<Spec> specs;
  final List<I18nText> highlights;

  /// Most a shopper can order at once; null when the product sets none.
  final int? maxPerOrder;
  final bool sameDay;
  final bool rfqEnabled;
  final int? rfqMinQty;
  final double ratingAvg;
  final int ratingCount;
  final int soldCount;

  /// In display order; the first is the main image.
  final List<ProductImage> images;

  /// Active variants, in the editor's order.
  final List<DetailVariant> variants;

  /// "You may also like" (C-05).
  final List<BrowseItem> related;
  final int? freeDeliveryCents;

  /// The options to choose between, e.g. colour then size, each with its
  /// values in variant order. A single variant has nothing to choose.
  List<OptionAxis> get axes {
    if (variants.length < 2) return const [];
    final values = <String, List<String>>{};
    for (final v in variants) {
      for (final e in v.attributes.entries) {
        final list = values.putIfAbsent(e.key, () => []);
        if (!list.contains(e.value)) list.add(e.value);
      }
    }
    return [for (final e in values.entries) OptionAxis(e.key, e.value)];
  }

  /// Every value of [axis] across variants, e.g. all colours ("Black, White,
  /// Sky" on C-05a).
  List<String> valuesOf(String axis) => [
    for (final a in axes)
      if (a.key == axis) ...a.values,
  ];

  /// The index in [images] of [variant]'s first photo, if it has one.
  int? imageIndexFor(DetailVariant variant) {
    final i = images.indexWhere((img) => img.variantId == variant.id);
    return i < 0 ? null : i;
  }

  bool get soldOut => variants.every((v) => !v.inStock);
}

class ProductImage {
  const ProductImage({
    required this.url,
    this.alt = const I18nText(),
    this.variantId,
  });

  final String url;
  final I18nText alt;

  /// The colour this photo shows, when it is linked to one.
  final String? variantId;
}

class DetailVariant {
  const DetailVariant({
    required this.id,
    required this.sku,
    this.attributes = const {},
    this.priceCents,
    this.compareAtCents,
    this.available = 0,
    this.lowStock = false,
  });

  final String id;
  final String sku;
  final Map<String, String> attributes;
  final int? priceCents;
  final int? compareAtCents;

  /// On hand minus held, over every warehouse (CAT-05).
  final int available;

  /// At or under its alert level (F10), so the page says "Only N left".
  final bool lowStock;

  bool get inStock => available > 0;

  StockState get stock => !inStock
      ? const OutOfStock()
      : lowStock
      ? LowStock(available)
      : const InStock();

  /// "Black", or "White · M" when there are several attributes.
  String get label => attributes.values.join(' · ');
}

class OptionAxis {
  const OptionAxis(this.key, this.values);

  /// The attribute key, e.g. `colour`.
  final String key;
  final List<String> values;

  bool get isColour => key == 'colour' || key == 'color';
}

sealed class StockState {
  const StockState();
}

class InStock extends StockState {
  const InStock();
}

class LowStock extends StockState {
  const LowStock(this.left);
  final int left;
}

class OutOfStock extends StockState {
  const OutOfStock();
}

/// Which variant is chosen on C-05 and C-05c. Out-of-stock values can't be
/// picked (App Flow F3); picking a value that doesn't combine with the other
/// choices moves them to the nearest variant that has it.
class VariantSelection {
  const VariantSelection._(this.product, this.chosen);

  /// Starts on the first variant that can be ordered, or the first one.
  factory VariantSelection.initial(ProductDetail product) {
    final start = product.variants.firstWhere(
      (v) => v.inStock,
      orElse: () => product.variants.isEmpty
          ? const DetailVariant(id: '', sku: '')
          : product.variants.first,
    );
    return VariantSelection._(product, {...start.attributes});
  }

  final ProductDetail product;
  final Map<String, String> chosen;

  /// The variant matching every choice.
  DetailVariant? get variant {
    for (final v in product.variants) {
      if (_matches(v, chosen)) return v;
    }
    return null;
  }

  String? valueOf(String axis) => chosen[axis];

  /// Whether [value] of [axis] can be picked with the other choices kept:
  /// such a variant exists and has stock.
  bool isEnabled(String axis, String value) {
    final others = {...chosen, axis: value};
    return product.variants.any((v) => v.inStock && _matches(v, others));
  }

  /// Picks [value] for [axis]. When no variant has that value with the other
  /// choices, they move to the best variant that does (in stock first).
  VariantSelection select(String axis, String value) {
    final wanted = {...chosen, axis: value};
    if (product.variants.any((v) => _matches(v, wanted))) {
      return VariantSelection._(product, wanted);
    }
    final withValue = product.variants
        .where((v) => v.attributes[axis] == value)
        .toList();
    if (withValue.isEmpty) return this;
    final next = withValue.firstWhere(
      (v) => v.inStock,
      orElse: () => withValue.first,
    );
    return VariantSelection._(product, {...next.attributes});
  }

  /// Most of this variant a shopper can add: the product's per-order limit,
  /// what is in stock, and the cart line cap. 0 when it can't be ordered.
  int get maxQty {
    final v = variant;
    if (v == null || !v.inStock) return 0;
    return [
      product.maxPerOrder ?? ProductDetail.cartLineMax,
      v.available,
      ProductDetail.cartLineMax,
    ].reduce(math.min);
  }

  static bool _matches(DetailVariant v, Map<String, String> wanted) =>
      wanted.entries.every((e) => v.attributes[e.key] == e.value);
}

/// Specifications in either stored shape: the F09 editor's ordered
/// `[{name, value}]`, or an older object whose keys read as labels
/// (`weight_g` → "Weight g").
List<Spec> specRowsFrom(Object? json) => switch (json) {
  final List<dynamic> list => [
    for (final s in list)
      if (s is Map && '${s['name'] ?? ''}'.trim().isNotEmpty)
        Spec(name: '${s['name']}'.trim(), value: '${s['value'] ?? ''}'.trim()),
  ],
  final Map<dynamic, dynamic> map => [
    for (final e in map.entries)
      Spec(name: humaniseKey(e.key.toString()), value: e.value.toString()),
  ],
  _ => const [],
};

/// `warranty_months` → "Warranty months".
String humaniseKey(String key) {
  final words = key.trim().replaceAll(RegExp(r'[_\-]+'), ' ');
  if (words.isEmpty) return words;
  return words[0].toUpperCase() + words.substring(1);
}

/// Swatch colours for the colour names the catalogue uses, as ARGB. Unknown
/// names get a neutral grey; the name is always shown with it.
int colourSwatch(String name) =>
    _swatches[name.trim().toLowerCase()] ?? 0xFF94A3B8;

const _swatches = <String, int>{
  'black': 0xFF1E293B,
  'white': 0xFFF8FAFC,
  'sky': 0xFF7DD3FC,
  'blue': 0xFF2563EB,
  'navy': 0xFF1E3A8A,
  'grey': 0xFF94A3B8,
  'gray': 0xFF94A3B8,
  'silver': 0xFFCBD5E1,
  'olive': 0xFF65743A,
  'green': 0xFF16A34A,
  'sand': 0xFFE7D3B0,
  'beige': 0xFFE7D3B0,
  'brown': 0xFF92400E,
  'red': 0xFFDC2626,
  'pink': 0xFFF9A8D4,
  'purple': 0xFF7C3AED,
  'yellow': 0xFFFACC15,
  'orange': 0xFFF97316,
  'gold': 0xFFD4A017,
};
