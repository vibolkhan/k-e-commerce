import '../../catalog/domain/i18n_text.dart';
import 'storefront.dart';

/// Suggestions start after this many characters (App Flow F3).
const minSuggestChars = 2;

/// Recent searches shown on C-04.
const recentSearchLimit = 8;

/// US-02: results within a second for typical queries. Slower searches are
/// logged as warnings.
const searchBudget = Duration(seconds: 1);

/// The query the way the server keeps it (`search_normalize`): trimmed,
/// single spaces, lowercase, at most 100 characters.
String normalizeSearch(String query) {
  final q = query.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  return q.length > 100 ? q.substring(0, 100) : q;
}

/// [query] moved to the front of [recent], once, keeping [limit].
List<String> pushRecent(
  List<String> recent,
  String query, {
  int limit = recentSearchLimit,
}) {
  final q = normalizeSearch(query);
  if (q.isEmpty) return recent;
  return [q, ...recent.where((r) => r != q)].take(limit).toList();
}

/// A run of [text] that does or doesn't match the query, for bolding.
typedef TextRun = ({String text, bool match});

/// [text] split around the first case-insensitive occurrence of [query]
/// (C-04 bolds the typed part in product names and the completion in
/// suggested words).
List<TextRun> matchRuns(String text, String query) {
  final q = query.trim();
  final at = q.isEmpty ? -1 : text.toLowerCase().indexOf(q.toLowerCase());
  if (at < 0) return [(text: text, match: false)];
  return [
    if (at > 0) (text: text.substring(0, at), match: false),
    (text: text.substring(at, at + q.length), match: true),
    if (at + q.length < text.length)
      (text: text.substring(at + q.length), match: false),
  ];
}

/// A word or phrase from the catalog that completes (or, when [fuzzy],
/// corrects) what is being typed.
class SuggestedTerm {
  const SuggestedTerm(this.term, {this.fuzzy = false});

  final String term;
  final bool fuzzy;
}

/// "headphones in Audio": the first term within its main category.
class SuggestedScope {
  const SuggestedScope({required this.term, required this.category});

  final String term;
  final StoreCategory category;
}

/// A product row in the suggestions. [priceCents] is null for business
/// buyers.
class SuggestedProduct {
  const SuggestedProduct({
    required this.id,
    required this.name,
    this.brand,
    this.priceCents,
    this.category,
    this.imageUrl,
  });

  final String id;
  final I18nText name;
  final String? brand;
  final int? priceCents;
  final I18nText? category;
  final String? imageUrl;
}

/// What `catalog_suggest` returns while the shopper types (C-04).
class SearchSuggestions {
  const SearchSuggestions({
    this.terms = const [],
    this.scope,
    this.products = const [],
  });

  factory SearchSuggestions.fromJson(
    Map<String, dynamic> json, {
    required String Function(String path) imageUrl,
  }) {
    final scope = json['scope'];
    final category = scope is Map ? scope['category'] : null;
    return SearchSuggestions(
      terms: [
        for (final t in json['terms'] as List? ?? const [])
          SuggestedTerm(
            (t as Map)['term'] as String,
            fuzzy: t['fuzzy'] == true,
          ),
      ],
      scope: category is Map
          ? SuggestedScope(
              term: scope['term'] as String,
              category: StoreCategory(
                id: category['id'] as String,
                slug: category['slug'] as String? ?? '',
                name: I18nText.fromJson(category['name']),
              ),
            )
          : null,
      products: [
        for (final p in json['products'] as List? ?? const [])
          _product(p as Map<String, dynamic>, imageUrl),
      ],
    );
  }

  static SuggestedProduct _product(
    Map<String, dynamic> row,
    String Function(String path) imageUrl,
  ) {
    final image = row['main_image'] as String?;
    final category = row['category'];
    return SuggestedProduct(
      id: row['id'] as String,
      name: I18nText.fromJson(row['name']),
      brand: row['brand'] as String?,
      priceCents: (row['min_price_cents'] as num?)?.toInt(),
      category: category == null ? null : I18nText.fromJson(category),
      imageUrl: image == null || image.isEmpty ? null : imageUrl(image),
    );
  }

  static const empty = SearchSuggestions();

  final List<SuggestedTerm> terms;
  final SuggestedScope? scope;
  final List<SuggestedProduct> products;

  bool get isEmpty => terms.isEmpty && products.isEmpty;
}
