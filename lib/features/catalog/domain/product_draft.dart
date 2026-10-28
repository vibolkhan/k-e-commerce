import 'i18n_text.dart';

/// `product_status`: draft → active → archived (restore goes back to draft).
enum ProductStatus {
  draft,
  active,
  archived;

  static ProductStatus fromDb(Object? value) => values.firstWhere(
    (s) => s.name == value,
    orElse: () => ProductStatus.draft,
  );
}

/// Limits shared with catalog-manage (supabase/functions/_shared/catalog_flows.ts).
abstract final class CatalogLimits {
  static const name = 120;
  static const description = 1000;
  static const highlights = 10;
  static const highlight = 120;
  static const specs = 30;
  static const tags = 20;
  static const options = 3;
  static const variants = 100;
  static const images = 10;
  static const alt = 200;
  static const maxPriceCents = 10000000;
  static const maxQty = 1000000;
  static const maxRfqQty = 100000;

  /// Product images bucket limit (F04): 5 MB, JPG/PNG/WebP.
  static const imageBytes = 5 * 1024 * 1024;
}

final skuPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$');

class Spec {
  const Spec({this.name = '', this.value = ''});

  final String name;
  final String value;

  Spec copyWith({String? name, String? value}) =>
      Spec(name: name ?? this.name, value: value ?? this.value);

  @override
  bool operator ==(Object other) =>
      other is Spec && other.name == name && other.value == value;

  @override
  int get hashCode => Object.hash(name, value);
}

/// An option such as Colour with its values (A-05b Options card).
class ProductOption {
  const ProductOption({this.name = const I18nText(), this.values = const []});

  factory ProductOption.fromJson(Map<String, dynamic> json) => ProductOption(
    name: I18nText.fromJson(json['name']),
    values: [
      for (final v in (json['values'] as List? ?? const [])) v.toString(),
    ],
  );

  final I18nText name;
  final List<String> values;

  ProductOption copyWith({I18nText? name, List<String>? values}) =>
      ProductOption(name: name ?? this.name, values: values ?? this.values);

  Map<String, dynamic> toJson() => {'name': name.toJson(), 'values': values};

  @override
  bool operator ==(Object other) =>
      other is ProductOption &&
      other.name == name &&
      _listEquals(other.values, values);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(values));
}

class VariantDraft {
  const VariantDraft({
    this.id,
    this.sku = '',
    this.barcode = '',
    this.attributes = const {},
    this.active = true,
    this.priceCents,
    this.compareAtCents,
    this.initialQty,
    this.onHand = 0,
    this.reserved = 0,
    this.lowStockAt = 0,
    this.stocked = false,
  });

  /// Null for a variant that isn't saved yet.
  final String? id;
  final String sku;
  final String barcode;
  final Map<String, String> attributes;

  /// The "Sell" switch.
  final bool active;
  final int? priceCents;
  final int? compareAtCents;

  /// Opening stock; new variants only (later changes are A-06, F10).
  final int? initialQty;

  /// Read-only, from `stock`.
  final int onHand;
  final int reserved;
  final int lowStockAt;
  final bool stocked;

  bool get isNew => id == null;
  int get available => onHand - reserved;

  /// "Black / M", or the SKU when there are no options.
  String label() => attributes.isEmpty ? sku : attributes.values.join(' / ');

  VariantDraft copyWith({
    String? sku,
    String? barcode,
    Map<String, String>? attributes,
    bool? active,
    int? Function()? priceCents,
    int? Function()? initialQty,
  }) => VariantDraft(
    id: id,
    sku: sku ?? this.sku,
    barcode: barcode ?? this.barcode,
    attributes: attributes ?? this.attributes,
    active: active ?? this.active,
    priceCents: priceCents != null ? priceCents() : this.priceCents,
    compareAtCents: compareAtCents,
    initialQty: initialQty != null ? initialQty() : this.initialQty,
    onHand: onHand,
    reserved: reserved,
    lowStockAt: lowStockAt,
    stocked: stocked,
  );

  Map<String, dynamic> toJson() => {
    'id': ?id,
    'sku': sku.trim(),
    if (barcode.trim().isNotEmpty) 'barcode': barcode.trim(),
    'attributes': attributes,
    'active': active,
    'price_cents': ?priceCents,
    'compare_at_cents': ?compareAtCents,
    if (isNew && initialQty != null) 'initial_qty': initialQty,
  };

  @override
  bool operator ==(Object other) =>
      other is VariantDraft &&
      other.id == id &&
      other.sku == sku &&
      other.barcode == barcode &&
      _mapEquals(other.attributes, attributes) &&
      other.active == active &&
      other.priceCents == priceCents &&
      other.initialQty == initialQty;

  @override
  int get hashCode => Object.hash(id, sku, barcode, active, priceCents);
}

class ImageDraft {
  const ImageDraft({
    this.id,
    required this.path,
    required this.url,
    this.alt = const I18nText(),
    this.variantSku,
  });

  final String? id;

  /// In the product-images bucket, e.g. `products/<id>/<file>.jpg`.
  final String path;

  /// Public URL to show it.
  final String url;
  final I18nText alt;
  final String? variantSku;

  ImageDraft copyWith({I18nText? alt, String? Function()? variantSku}) =>
      ImageDraft(
        id: id,
        path: path,
        url: url,
        alt: alt ?? this.alt,
        variantSku: variantSku != null ? variantSku() : this.variantSku,
      );

  Map<String, dynamic> toJson() => {
    'id': ?id,
    'path': path,
    'alt': alt.toJson(),
    'variant_sku': ?variantSku,
  };

  @override
  bool operator ==(Object other) =>
      other is ImageDraft &&
      other.id == id &&
      other.path == path &&
      other.alt == alt &&
      other.variantSku == variantSku;

  @override
  int get hashCode => Object.hash(id, path, alt, variantSku);
}

/// Who and when, for the A-05a Summary card. Read-only.
class ProductSummary {
  const ProductSummary({
    this.createdAt,
    this.createdBy,
    this.updatedAt,
    this.updatedBy,
    this.soldCount = 0,
    this.ratingAvg = 0,
    this.ratingCount = 0,
  });

  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? updatedAt;
  final String? updatedBy;
  final int soldCount;
  final double ratingAvg;
  final int ratingCount;
}

/// The product editor's state (A-05a – A-05c): everything catalog-manage
/// saves in one call.
class ProductDraft {
  const ProductDraft({
    this.id,
    this.categoryId,
    this.slug = '',
    this.brand = '',
    this.name = const I18nText(),
    this.description = const I18nText(),
    this.highlights = const [],
    this.specs = const [],
    this.tags = const [],
    this.options = const [],
    this.status = ProductStatus.draft,
    this.isBestSeller = false,
    this.sameDay = true,
    this.rfqEnabled = false,
    this.rfqMinQty,
    this.rfqMultiple = 1,
    this.variants = const [VariantDraft()],
    this.images = const [],
    this.summary = const ProductSummary(),
  });

  final String? id;
  final String? categoryId;
  final String slug;
  final String brand;
  final I18nText name;
  final I18nText description;
  final List<I18nText> highlights;
  final List<Spec> specs;
  final List<String> tags;
  final List<ProductOption> options;
  final ProductStatus status;
  final bool isBestSeller;
  final bool sameDay;
  final bool rfqEnabled;
  final int? rfqMinQty;
  final int rfqMultiple;
  final List<VariantDraft> variants;

  /// In display order; the first is the main image.
  final List<ImageDraft> images;
  final ProductSummary summary;

  bool get isNew => id == null;
  ImageDraft? get mainImage => images.isEmpty ? null : images.first;
  int get imagesMissingAlt =>
      images.where((i) => i.alt.en.trim().isEmpty).length;

  ProductDraft copyWith({
    String? Function()? categoryId,
    String? brand,
    I18nText? name,
    I18nText? description,
    List<I18nText>? highlights,
    List<Spec>? specs,
    List<String>? tags,
    List<ProductOption>? options,
    ProductStatus? status,
    bool? isBestSeller,
    bool? sameDay,
    bool? rfqEnabled,
    int? Function()? rfqMinQty,
    int? rfqMultiple,
    List<VariantDraft>? variants,
    List<ImageDraft>? images,
  }) => ProductDraft(
    id: id,
    categoryId: categoryId != null ? categoryId() : this.categoryId,
    slug: slug,
    brand: brand ?? this.brand,
    name: name ?? this.name,
    description: description ?? this.description,
    highlights: highlights ?? this.highlights,
    specs: specs ?? this.specs,
    tags: tags ?? this.tags,
    options: options ?? this.options,
    status: status ?? this.status,
    isBestSeller: isBestSeller ?? this.isBestSeller,
    sameDay: sameDay ?? this.sameDay,
    rfqEnabled: rfqEnabled ?? this.rfqEnabled,
    rfqMinQty: rfqMinQty != null ? rfqMinQty() : this.rfqMinQty,
    rfqMultiple: rfqMultiple ?? this.rfqMultiple,
    variants: variants ?? this.variants,
    images: images ?? this.images,
    summary: summary,
  );

  /// The catalog-manage `save` body's `product`. Archived products keep
  /// their status (restore is its own action).
  Map<String, dynamic> toPayload() => {
    'id': ?id,
    'category_id': categoryId,
    if (slug.isNotEmpty) 'slug': slug,
    if (brand.trim().isNotEmpty) 'brand': brand.trim(),
    'name': name.toJson(),
    'description': description.toJson(),
    'highlights': [
      for (final h in highlights)
        if (!h.isEmpty) h.toJson(),
    ],
    'specs': [
      for (final s in specs)
        if (s.name.trim().isNotEmpty || s.value.trim().isNotEmpty)
          {'name': s.name.trim(), 'value': s.value.trim()},
    ],
    'tags': tags,
    'options': [for (final o in options) o.toJson()],
    'status': status == ProductStatus.active ? 'active' : 'draft',
    'is_best_seller': isBestSeller,
    'same_day': sameDay,
    'rfq_enabled': rfqEnabled,
    'rfq_min_qty': ?rfqMinQty,
    'rfq_multiple': rfqMultiple,
    'variants': [for (final v in variants) v.toJson()],
    'images': [for (final i in images) i.toJson()],
  };

  /// What the editor checks before calling the server; the same rules and
  /// field paths as catalog-manage, so server answers land on the same fields.
  List<FieldIssue> validate() {
    final issues = <FieldIssue>[];
    void fail(String field, IssueCode code) =>
        issues.add(FieldIssue(field, code));

    if (name.en.trim().isEmpty) fail('name.en', IssueCode.required);
    if (name.en.trim().length > CatalogLimits.name) {
      fail('name.en', IssueCode.tooLong);
    }
    if (name.km.trim().length > CatalogLimits.name) {
      fail('name.km', IssueCode.tooLong);
    }
    if (description.en.trim().length > CatalogLimits.description) {
      fail('description.en', IssueCode.tooLong);
    }
    if (description.km.trim().length > CatalogLimits.description) {
      fail('description.km', IssueCode.tooLong);
    }
    if (categoryId == null) fail('category_id', IssueCode.required);

    if (variants.isEmpty) fail('variants', IssueCode.required);
    final seen = <String>{};
    for (var i = 0; i < variants.length; i++) {
      final v = variants[i];
      final sku = v.sku.trim();
      if (sku.isEmpty) {
        fail('variants.$i.sku', IssueCode.required);
      } else if (!skuPattern.hasMatch(sku)) {
        fail('variants.$i.sku', IssueCode.invalid);
      } else if (!seen.add(sku.toUpperCase())) {
        fail('variants.$i.sku', IssueCode.duplicate);
      }
      final price = v.priceCents;
      if (price == null) {
        fail('variants.$i.price_cents', IssueCode.required);
      } else if (price < 1 || price > CatalogLimits.maxPriceCents) {
        fail('variants.$i.price_cents', IssueCode.invalid);
      }
      final qty = v.initialQty;
      if (qty != null && (qty < 0 || qty > CatalogLimits.maxQty)) {
        fail('variants.$i.initial_qty', IssueCode.invalid);
      }
    }

    if (rfqEnabled && rfqMinQty == null) {
      fail('rfq_min_qty', IssueCode.required);
    }
    final min = rfqMinQty;
    if (min != null && (min < 1 || min > CatalogLimits.maxRfqQty)) {
      fail('rfq_min_qty', IssueCode.invalid);
    }
    if (rfqMultiple < 1 || rfqMultiple > CatalogLimits.maxRfqQty) {
      fail('rfq_multiple', IssueCode.invalid);
    }

    for (var i = 0; i < images.length; i++) {
      if (images[i].alt.en.trim().isEmpty) {
        fail('images.$i.alt', IssueCode.required);
      }
    }
    if (images.length > CatalogLimits.images) {
      fail('images', IssueCode.tooMany);
    }
    return issues;
  }

  /// Everything the staff member can change, for the unsaved-changes check.
  bool sameContentAs(ProductDraft other) =>
      other.categoryId == categoryId &&
      other.brand == brand &&
      other.name == name &&
      other.description == description &&
      _listEquals(other.highlights, highlights) &&
      _listEquals(other.specs, specs) &&
      _listEquals(other.tags, tags) &&
      _listEquals(other.options, options) &&
      other.status == status &&
      other.isBestSeller == isBestSeller &&
      other.sameDay == sameDay &&
      other.rfqEnabled == rfqEnabled &&
      other.rfqMinQty == rfqMinQty &&
      other.rfqMultiple == rfqMultiple &&
      _listEquals(other.variants, variants) &&
      _listEquals(other.images, images);
}

enum IssueCode {
  required,
  tooLong,
  tooMany,
  invalid,
  duplicate;

  static IssueCode fromWire(Object? code) => switch (code) {
    'required' => required,
    'too_long' => tooLong,
    'too_many' => tooMany,
    'duplicate' => duplicate,
    _ => invalid,
  };
}

/// A problem with one field. [field] is a dotted path as catalog-manage
/// reports it: `name.en`, `variants.2.sku`, `images.0.alt`.
class FieldIssue {
  const FieldIssue(this.field, this.code);

  final String field;
  final IssueCode code;

  /// Which editor tab shows the field.
  ProductTab get tab {
    if (field.startsWith('variants') ||
        field.startsWith('options') ||
        field.startsWith('rfq')) {
      return ProductTab.variants;
    }
    if (field.startsWith('images')) return ProductTab.images;
    return ProductTab.general;
  }

  @override
  bool operator ==(Object other) =>
      other is FieldIssue && other.field == field && other.code == code;

  @override
  int get hashCode => Object.hash(field, code);

  @override
  String toString() => 'FieldIssue($field, ${code.name})';
}

enum ProductTab { general, variants, images }

/// Every combination of the option values, in option order: Colour
/// [Black, White] × Size [M, L] gives Black/M, Black/L, White/M, White/L.
/// Variants that already exist for a combination are kept (with their SKU,
/// price and id); variants matching no combination are dropped unless saved,
/// in which case they stay but stop selling.
List<VariantDraft> variantsForOptions(
  List<ProductOption> options,
  List<VariantDraft> current, {
  String skuPrefix = '',
}) {
  final usable = [
    for (final o in options)
      if (o.name.en.trim().isNotEmpty && o.values.isNotEmpty) o,
  ];
  if (usable.isEmpty) return current;

  var combos = <Map<String, String>>[{}];
  for (final option in usable) {
    combos = [
      for (final combo in combos)
        for (final value in option.values)
          {...combo, option.name.en.trim(): value},
    ];
  }

  final used = <VariantDraft>{};
  final result = <VariantDraft>[];
  final defaultPrice = current
      .map((v) => v.priceCents)
      .firstWhere((p) => p != null, orElse: () => null);
  for (final combo in combos) {
    final match = current.where((v) => _mapEquals(v.attributes, combo));
    if (match.isNotEmpty) {
      used.add(match.first);
      result.add(match.first);
      continue;
    }
    result.add(
      VariantDraft(
        sku: skuPrefix.isEmpty ? '' : skuFor(skuPrefix, combo.values),
        attributes: combo,
        priceCents: defaultPrice,
      ),
    );
  }
  for (final v in current) {
    if (!used.contains(v) && !v.isNew) result.add(v.copyWith(active: false));
  }
  return result;
}

/// `HP-PRO` + [White, 42] → `HP-PRO-WHT-42`: each value is its first letter
/// and following consonants, at most three characters.
String skuFor(String prefix, Iterable<String> values) {
  String code(String value) {
    final clean = value.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    if (clean.isEmpty) return '';
    final rest = clean.substring(1).replaceAll(RegExp('[AEIOU]'), '');
    final out = clean[0] + rest;
    return out.length > 3 ? out.substring(0, 3) : out;
  }

  return [
    prefix.trim().toUpperCase(),
    for (final value in values)
      if (code(value).isNotEmpty) code(value),
  ].where((p) => p.isNotEmpty).join('-');
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}
