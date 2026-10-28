import 'i18n_text.dart';

/// A product as customers get it: what RLS lets them read (F04). Business
/// buyers can't read prices, so [variants] carry no price for them and
/// [fromPriceCents] is null (Q8: "Price on quote").
class ProductView {
  const ProductView({
    required this.id,
    required this.slug,
    required this.name,
    this.description = const I18nText(),
    this.brand,
    this.imageUrls = const [],
    this.imageAlts = const [],
    this.variants = const [],
    this.rfqEnabled = false,
    this.rfqMinQty,
    this.ratingAvg = 0,
    this.ratingCount = 0,
  });

  final String id;
  final String slug;
  final I18nText name;
  final I18nText description;
  final String? brand;

  /// In display order; the first is the main image.
  final List<String> imageUrls;
  final List<I18nText> imageAlts;
  final List<VariantView> variants;
  final bool rfqEnabled;
  final int? rfqMinQty;
  final double ratingAvg;
  final int ratingCount;

  String? get mainImageUrl => imageUrls.isEmpty ? null : imageUrls.first;

  /// The lowest price a customer can buy at; null when no price is readable.
  int? get fromPriceCents {
    final prices = [
      for (final v in variants)
        if (v.priceCents != null) v.priceCents!,
    ];
    if (prices.isEmpty) return null;
    return prices.reduce((a, b) => a < b ? a : b);
  }

  /// Every variant sold out (CAT-05).
  bool get soldOut => variants.every((v) => v.available <= 0);
}

class VariantView {
  const VariantView({
    required this.id,
    required this.sku,
    this.attributes = const {},
    this.priceCents,
    this.available = 0,
  });

  final String id;
  final String sku;
  final Map<String, String> attributes;
  final int? priceCents;
  final int available;
}
