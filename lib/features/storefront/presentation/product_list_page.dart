import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_role.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/ui/k_ui.dart';
import '../../../core/utils/log.dart';
import '../../catalog/domain/i18n_text.dart';
import '../data/storefront_repository.dart';
import '../domain/browse.dart';
import '../domain/storefront.dart';
import 'filter_sheet.dart';
import 'home_page.dart' show storeMaxWidth;
import 'sort_sheet.dart';
import 'store_widgets.dart';
import 'storefront_providers.dart';

/// C-03 Product list for a category (with its subcategories) or a
/// collection: quick chips, the filter (C-03a) and sort (C-03b) sheets, and
/// a grid that loads the next page as you scroll.
class ProductListPage extends ConsumerStatefulWidget {
  const ProductListPage({
    super.key,
    required this.role,
    this.categorySlug,
    this.collection,
  }) : assert((categorySlug == null) != (collection == null));

  final AppRole role;
  final String? categorySlug;
  final String? collection;

  @override
  ConsumerState<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends ConsumerState<ProductListPage> {
  final _scroll = ScrollController();

  /// Null until the category is resolved.
  BrowseQuery? _query;
  final _items = <BrowseItem>[];
  BrowsePage _last = BrowsePage.empty;
  bool _loading = true;
  bool _loadingMore = false;
  bool _failed = false;

  /// Bumped on every new query so late answers to old ones are dropped.
  int _generation = 0;

  bool get _business => widget.role == AppRole.business;
  bool get _hasMore => _items.length < _last.total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    if (widget.collection != null) {
      _start(BrowseQuery(collection: widget.collection));
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  StorefrontRepository get _repo => ref.read(storefrontRepositoryProvider);

  BrowseQuery _effective(BrowseQuery q) => _business ? q.forBusiness() : q;

  Future<void> _start(BrowseQuery query) async {
    final gen = ++_generation;
    setState(() {
      _query = query;
      _loading = true;
      _failed = false;
    });
    try {
      final page = await _repo.browse(_effective(query));
      if (!mounted || gen != _generation) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _last = page;
        _loading = false;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
    } catch (e) {
      log('Product list failed: $e');
      if (!mounted || gen != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _maybeLoadMore() async {
    final query = _query;
    if (query == null || _loading || _loadingMore || !_hasMore) return;
    if (!_scroll.hasClients || _scroll.position.extentAfter > 600) return;
    final gen = _generation;
    setState(() => _loadingMore = true);
    try {
      final next = query.atPage(_items.length ~/ query.pageSize);
      final page = await _repo.browse(_effective(next));
      if (!mounted || gen != _generation) return;
      setState(() {
        final seen = {for (final i in _items) i.id};
        _items.addAll(page.items.where((i) => !seen.contains(i.id)));
        _last = page;
        _loadingMore = false;
        // A short page means the list changed underneath; stop here.
        if (page.items.isEmpty) _last = _withTotal(page, _items.length);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
    } catch (e) {
      log('Next page failed: $e');
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  static BrowsePage _withTotal(BrowsePage p, int total) => BrowsePage(
    items: p.items,
    total: total,
    brands: p.brands,
    minPriceCents: p.minPriceCents,
    maxPriceCents: p.maxPriceCents,
    allSameDay: p.allSameDay,
  );

  void _update(BrowseQuery query) {
    if (query == _query) return;
    _start(query);
  }

  Future<void> _openFilters() async {
    final query = _query;
    if (query == null) return;
    final result = await showFilterSheet(
      context,
      query: query,
      facets: _last,
      business: _business,
      cutoff: cutoffLabel(
        AppLocalizations.of(context),
        (ref.read(storeClockProvider).value ?? StoreClock.local(DateTime.now()))
            .cutoff,
      ),
      count: (q) async => (await _repo.browse(_effective(q.atPage(0)))).total,
    );
    if (result != null) _update(result);
  }

  Future<void> _openSort() async {
    final query = _query;
    if (query == null) return;
    final sort = await showSortSheet(
      context,
      current: query.sort,
      business: _business,
    );
    if (sort != null) _update(query.copyWith(sort: sort));
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final shell = widget.role.homePath;

    String title;
    var notFound = false;
    var treeFailed = false;
    if (widget.categorySlug != null) {
      final tree = ref.watch(storeCategoriesProvider);
      final category = tree.value?.bySlug(widget.categorySlug!);
      title = category?.name.of(lang) ?? '';
      notFound = tree.hasValue && category == null;
      treeFailed = tree.hasError && !tree.hasValue;
      if (_query == null && category != null) {
        final q = BrowseQuery(categoryId: category.id);
        // Starting a load calls setState; not during build.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _query == null) _start(q);
        });
      }
    } else {
      title =
          ref
              .watch(collectionTitleProvider(widget.collection!))
              .value
              ?.of(lang) ??
          '';
    }

    return Scaffold(
      backgroundColor: k.colors.bg,
      appBar: KAppBar(
        title: title,
        centerTitle: false,
        line: true,
        showBack: true,
        onBack: () => context.canPop()
            ? context.pop()
            : context.go(
                widget.collection != null ? shell : AppRoutes.categories(shell),
              ),
        actions: [
          KIconButton(
            icon: KIcons.search,
            label: title.isEmpty
                ? l10n.storeSearchProducts
                : l10n.storeSearchIn(title),
            onPressed: () => context.push(AppRoutes.search(shell)),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: storeMaxWidth),
          child: notFound
              ? KEmptyState(
                  icon: KIcons.categories,
                  title: l10n.storeCategoryMissing,
                  action: KButton.outline(
                    label: l10n.storeBrowseCategories,
                    onPressed: () => context.go(AppRoutes.categories(shell)),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_query != null) _toolbar(context, _query!),
                    Expanded(child: _results(context, treeFailed)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context, BrowseQuery q) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final filters = q.activeFilterCount;
    return Container(
      decoration: BoxDecoration(
        color: k.colors.surface,
        border: Border(bottom: BorderSide(color: k.colors.line)),
      ),
      child: Semantics(
        label: l10n.storeFilterAndSort,
        container: true,
        explicitChildNodes: true,
        child: SingleChildScrollView(
          key: const Key('chip-toolbar'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              KChip(
                key: const Key('chip-filters'),
                label: l10n.storeFilters,
                icon: KIcons.filter,
                selected: filters > 0,
                count: filters > 0 ? filters : null,
                onTap: _openFilters,
              ),
              const SizedBox(width: 8),
              KChip(
                key: const Key('chip-sort'),
                label: l10n.storeSortChip(sortLabel(l10n, q.sort, short: true)),
                icon: KIcons.sort,
                onTap: _openSort,
              ),
              const SizedBox(width: 8),
              KChip(
                key: const Key('chip-in-stock'),
                label: l10n.storeInStock,
                icon: q.inStock ? KIcons.check : null,
                selected: q.inStock,
                onTap: () => _update(q.copyWith(inStock: !q.inStock)),
              ),
              if (!_business) ...[
                const SizedBox(width: 8),
                KChip(
                  key: const Key('chip-under'),
                  label: l10n.storeUnderPrice('\$50'),
                  selected: q.isUnderChipOn,
                  onTap: () => _update(
                    q.isUnderChipOn
                        ? q.copyWith(minCents: () => null, maxCents: () => null)
                        : q.copyWith(
                            minCents: () => null,
                            maxCents: () => BrowseQuery.underChipCents,
                          ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              KChip(
                key: const Key('chip-rating'),
                label: l10n.storeRatingAndUp('4'),
                icon: KIcons.star,
                selected: q.minRating == 4,
                onTap: () => _update(
                  q.copyWith(minRating: () => q.minRating == 4 ? null : 4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results(BuildContext context, bool treeFailed) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final query = _query;
    if (_failed || treeFailed) {
      return KEmptyState(
        icon: KIcons.error,
        title: l10n.storeLoadFailed,
        action: KButton.outline(
          label: l10n.storeRetry,
          onPressed: () {
            if (query != null) {
              _start(query);
            } else {
              ref.invalidate(storeCategoriesProvider);
            }
          },
        ),
      );
    }
    if (_loading || query == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const KSkeleton(width: 100, height: 14),
          const SizedBox(height: 12),
          StoreProductGrid(
            children: [for (var i = 0; i < 6; i++) const ProductCardSkeleton()],
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      final filtered = query.activeFilterCount > 0;
      return ListView(
        children: [
          KEmptyState(
            icon: filtered ? KIcons.filter : KIcons.package,
            title: filtered ? l10n.storeNoMatches : l10n.storeCategoryEmpty,
            message: filtered
                ? l10n.storeNoMatchesBody
                : l10n.storeCategoryEmptyBody,
            action: filtered
                ? KButton.outline(
                    key: const Key('clear-filters'),
                    label: l10n.storeClearFilters,
                    onPressed: () => _update(query.cleared()),
                  )
                : KButton.outline(
                    label: l10n.storeBrowseCategories,
                    onPressed: () =>
                        context.go(AppRoutes.categories(widget.role.homePath)),
                  ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: () => _start(query),
      child: ListView(
        key: const Key('product-list'),
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.storeProductCount(_last.total),
                  style: k.text.small.copyWith(
                    fontWeight: FontWeight.w600,
                    color: k.colors.ink2,
                  ),
                ),
              ),
              if (_last.allSameDay && !_business) ...[
                KIcon(KIcons.delivery, size: 16, color: k.colors.muted),
                const SizedBox(width: 4),
                Text(
                  l10n.storeAllSameDay,
                  style: k.text.caption.copyWith(color: k.colors.muted),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          StoreProductGrid(
            children: [
              for (final item in _items)
                StoreProductCard(
                  key: ValueKey(item.id),
                  item: item,
                  role: widget.role,
                ),
            ],
          ),
          if (_hasMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: KSpinner(blue: true)),
            ),
        ],
      ),
    );
  }
}

/// The collection's title for the app bar.
final collectionTitleProvider = FutureProvider.family<I18nText?, String>(
  (ref, slug) => ref.watch(storefrontRepositoryProvider).collectionTitle(slug),
);
