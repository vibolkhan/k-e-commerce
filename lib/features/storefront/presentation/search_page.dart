import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_role.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/ui/k_ui.dart';
import '../../../core/utils/log.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/search_repository.dart';
import '../data/storefront_repository.dart';
import '../domain/browse.dart';
import '../domain/search.dart';
import '../domain/storefront.dart';
import 'filter_sheet.dart';
import 'home_page.dart' show storeMaxWidth;
import 'search_providers.dart';
import 'search_widgets.dart';
import 'sort_sheet.dart';
import 'store_widgets.dart';
import 'storefront_providers.dart';

/// C-04 Search. While typing: suggestions after 2 characters, recent
/// searches and popular categories. After a search: C-04a results with
/// Filters, Sort (Best match first) and In stock, or C-04b with "Did you
/// mean" when nothing matches. Every search is timed, logged and recorded.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, required this.role, this.initialQuery});

  final AppRole role;

  /// `?q=`: opens straight on its results.
  final String? initialQuery;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  /// Results pages hold this many rows ("Show N more results").
  static const pageSize = 20;

  /// Phones get list rows (C-04a); wider screens the product grid.
  static const rowsUpTo = 600.0;

  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// Typing (C-04) or looking at results (C-04a / C-04b).
  bool _typing = true;

  Timer? _debounce;
  SearchSuggestions _suggestions = SearchSuggestions.empty;
  String _suggestedFor = '';
  int _suggestGeneration = 0;

  /// The search on screen; null until the first one.
  BrowseQuery? _query;

  /// "headphones in Audio": the category the search was narrowed to.
  StoreCategory? _scope;
  final _items = <BrowseItem>[];
  BrowsePage _last = BrowsePage.empty;
  bool _loading = false;
  bool _loadingMore = false;
  bool _failed = false;
  String? _didYouMean;

  /// Bumped on every new query so late answers to old ones are dropped.
  int _generation = 0;

  bool get _business => widget.role == AppRole.business;
  String get _shell => widget.role.homePath;
  bool get _hasMore => _items.length < _last.total;

  StorefrontRepository get _store => ref.read(storefrontRepositoryProvider);
  SearchRepository get _search => ref.read(searchRepositoryProvider);

  BrowseQuery _effective(BrowseQuery q) => _business ? q.forBusiness() : q;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim() ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (initial.isNotEmpty) {
        _submit(initial);
      } else {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ typing

  void _onChanged(String text) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => _loadSuggestions(text),
    );
  }

  Future<void> _loadSuggestions(String text) async {
    final gen = ++_suggestGeneration;
    if (normalizeSearch(text).length < minSuggestChars) {
      if (mounted) setState(() => _suggestions = SearchSuggestions.empty);
      return;
    }
    try {
      final s = await _search.suggest(text);
      if (!mounted || gen != _suggestGeneration) return;
      setState(() {
        _suggestions = s;
        _suggestedFor = text.trim();
      });
    } catch (e) {
      log('Suggestions failed: $e');
    }
  }

  /// Back to typing, from the results' search box.
  void _edit({bool clear = false}) {
    if (clear) _controller.clear();
    setState(() => _typing = true);
    _focus.requestFocus();
    _loadSuggestions(_controller.text);
  }

  void _clearField() {
    _controller.clear();
    _onChanged('');
    _focus.requestFocus();
  }

  /// Cancel: back to the results if there are some, else leave.
  void _cancel() {
    final query = _query;
    if (query != null) {
      _controller.text = query.search ?? '';
      _focus.unfocus();
      setState(() => _typing = false);
    } else {
      _leave();
    }
  }

  void _leave() => context.canPop() ? context.pop() : context.go(_shell);

  // ----------------------------------------------------------- results

  void _submit(String text, {StoreCategory? scope}) {
    final q = text.trim();
    if (q.isEmpty) return;
    _debounce?.cancel();
    _controller.text = q;
    _focus.unfocus();
    setState(() {
      _typing = false;
      _scope = scope;
    });
    _start(
      BrowseQuery(
        search: q,
        categoryId: scope?.id,
        sort: BrowseSort.relevance,
        pageSize: pageSize,
      ),
      record: true,
    );
  }

  Future<void> _start(BrowseQuery query, {bool record = false}) async {
    final gen = ++_generation;
    setState(() {
      _query = query;
      _loading = true;
      _failed = false;
      _didYouMean = null;
    });
    final watch = Stopwatch()..start();
    try {
      final page = await _store.browse(_effective(query));
      final took = watch.elapsed;
      if (!mounted || gen != _generation) return;
      _logTiming(query, page.total, took);
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _last = page;
        _loading = false;
      });
      if (record) unawaited(_record(query.search!, page.total, took));
      if (page.total == 0 && query.activeFilterCount == 0) {
        unawaited(_suggestCorrection(query, gen));
      }
    } catch (e) {
      log('Search failed: $e');
      if (!mounted || gen != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  /// US-02: results in under a second. Every search is logged with its time
  /// here (debug) and on the server (`search_log`, with [record]).
  void _logTiming(BrowseQuery query, int total, Duration took) {
    final ms = took.inMilliseconds;
    final slow = took > searchBudget
        ? ' (over the ${searchBudget.inMilliseconds} ms budget)'
        : '';
    log('Search "${query.search}" found $total in $ms ms$slow');
  }

  Future<void> _record(String query, int results, Duration took) async {
    try {
      await _search.recordSearch(query, results: results, took: took);
    } catch (e) {
      log('Could not record the search: $e');
    }
    _refreshRecent();
  }

  Future<void> _suggestCorrection(BrowseQuery query, int gen) async {
    try {
      final better = await _search.didYouMean(query.search!);
      if (!mounted || gen != _generation) return;
      if (better != null && better != normalizeSearch(query.search!)) {
        setState(() => _didYouMean = better);
      }
    } catch (e) {
      log('Did you mean failed: $e');
    }
  }

  Future<void> _loadMore() async {
    final query = _query;
    if (query == null || _loading || _loadingMore || !_hasMore) return;
    final gen = _generation;
    setState(() => _loadingMore = true);
    try {
      final next = query.atPage(_items.length ~/ query.pageSize);
      final page = await _store.browse(_effective(next));
      if (!mounted || gen != _generation) return;
      setState(() {
        final seen = {for (final i in _items) i.id};
        _items.addAll(page.items.where((i) => !seen.contains(i.id)));
        _last = page.items.isEmpty
            ? BrowsePage(
                items: page.items,
                total: _items.length,
                brands: page.brands,
                minPriceCents: page.minPriceCents,
                maxPriceCents: page.maxPriceCents,
                allSameDay: page.allSameDay,
              )
            : page;
        _loadingMore = false;
      });
    } catch (e) {
      log('More results failed: $e');
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _update(BrowseQuery query) {
    if (query == _query) return;
    _start(query);
  }

  void _dropScope() {
    final query = _query;
    if (query == null) return;
    setState(() => _scope = null);
    _start(
      BrowseQuery(
        search: query.search,
        brands: query.brands,
        minCents: query.minCents,
        maxCents: query.maxCents,
        minRating: query.minRating,
        inStock: query.inStock,
        sameDay: query.sameDay,
        sort: query.sort,
        pageSize: query.pageSize,
      ),
    );
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
      count: (q) async => (await _store.browse(_effective(q.atPage(0)))).total,
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
      search: true,
    );
    if (sort != null) _update(query.copyWith(sort: sort));
  }

  Future<void> _clearRecent() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showKConfirm(
      context,
      title: l10n.storeClearRecentTitle,
      message: l10n.storeClearRecentBody,
      confirmLabel: l10n.storeClearRecent,
      cancelLabel: l10n.uiCancel,
      tone: KConfirmTone.destructive,
    );
    if (!ok || !mounted) return;
    try {
      await _search.clearRecentSearches();
    } catch (e) {
      log('Could not clear recent searches: $e');
    }
    _refreshRecent();
  }

  void _refreshRecent() {
    if (!mounted) return;
    final viewer = ref.read(authUserIdProvider).value;
    ref.invalidate(recentSearchesProvider(viewer));
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final typing = _typing;
    return PopScope(
      // Android back while editing a search returns to its results.
      canPop: !(typing && _query != null),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: typing ? k.colors.surface : k.colors.bg,
        appBar: _SearchBar(
          child: typing ? _typingBar(context) : _resultsBar(context),
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: storeMaxWidth),
            child: typing ? _typingBody(context) : _resultsBody(context),
          ),
        ),
      ),
    );
  }

  Widget _clearButton(VoidCallback onPressed) => KIconButton(
    key: const Key('search-clear'),
    icon: KIcons.close,
    label: AppLocalizations.of(context).storeSearchClear,
    onPressed: onPressed,
  );

  Widget _typingBar(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        const SizedBox(width: 16),
        Expanded(
          child: KTextField.search(
            key: const Key('search-field'),
            hint: _business
                ? l10n.storeSearchHintBusiness
                : l10n.storeSearchHint,
            controller: _controller,
            focusNode: _focus,
            onChanged: _onChanged,
            onSubmitted: _submit,
            suffix: _controller.text.isEmpty ? null : _clearButton(_clearField),
          ),
        ),
        const SizedBox(width: 4),
        KButton.ghost(
          key: const Key('search-cancel'),
          label: l10n.uiCancel,
          onPressed: _cancel,
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _resultsBar(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        const SizedBox(width: 6),
        KIconButton(
          key: const Key('search-back'),
          icon: KIcons.back,
          label: l10n.uiBack,
          onPressed: _leave,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: KTextField.search(
            key: const Key('search-field'),
            hint: _business
                ? l10n.storeSearchHintBusiness
                : l10n.storeSearchHint,
            controller: _controller,
            readOnly: true,
            onTap: _edit,
            suffix: _clearButton(() => _edit(clear: true)),
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _typingBody(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final viewer = watchViewer(ref);
    final recent = ref.watch(recentSearchesProvider(viewer)).value ?? const [];
    final popular = ref.watch(popularCategoriesProvider).value ?? const [];
    final text = _controller.text.trim();
    final showSuggestions =
        normalizeSearch(text).length >= minSuggestChars &&
        !_suggestions.isEmpty;
    return ListView(
      key: const Key('search-typing'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (showSuggestions) ...[
          Semantics(
            label: l10n.storeSuggestions,
            container: true,
            explicitChildNodes: true,
            child: Column(children: _suggestionRows(context)),
          ),
          Container(height: 8, color: k.colors.bg),
        ],
        if (recent.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SearchSectionHead(
                  title: l10n.storeRecentSearches,
                  action: KButton.ghost(
                    key: const Key('recent-clear'),
                    label: l10n.storeClearRecent,
                    size: KButtonSize.sm,
                    onPressed: _clearRecent,
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final q in recent)
                      KChip(
                        key: Key('recent-$q'),
                        label: q,
                        icon: KIcons.time,
                        onTap: () => _submit(q),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (popular.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SearchSectionHead(title: l10n.storePopularCategories),
                CategoryChips(categories: popular, shell: _shell),
              ],
            ),
          ),
        if (!showSuggestions && recent.isEmpty && popular.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.storeSearchStart,
              textAlign: TextAlign.center,
              style: k.text.small.copyWith(color: k.colors.muted),
            ),
          ),
      ],
    );
  }

  List<Widget> _suggestionRows(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final typed = _suggestedFor;
    final style = k.text.body.copyWith(color: k.colors.ink);
    InlineSpan termSpan(String term) => matchSpan(
      term,
      typed,
      style: style,
      matchWeight: FontWeight.w400,
      restWeight: FontWeight.w800,
    );
    final scope = _suggestions.scope;
    final rows = <Widget>[];
    for (final (i, t) in _suggestions.terms.indexed) {
      rows.add(
        SuggestionRow(
          key: Key('suggestion-term-$i'),
          title: termSpan(t.term),
          semanticLabel: t.term,
          onTap: () => _submit(t.term),
        ),
      );
      if (i == 0 && scope != null && scope.term == t.term) {
        final place = scope.category.name.of(lang);
        rows.add(
          SuggestionRow(
            key: const Key('suggestion-scope'),
            title: TextSpan(
              children: [
                termSpan(scope.term),
                TextSpan(
                  text: ' ${l10n.storeInCategory(place)}',
                  style: style.copyWith(color: k.colors.muted),
                ),
              ],
            ),
            semanticLabel: '${scope.term} ${l10n.storeInCategory(place)}',
            onTap: () => _submit(scope.term, scope: scope.category),
          ),
        );
      }
    }
    for (final p in _suggestions.products) {
      rows.add(
        SuggestedProductRow(
          key: Key('suggestion-product-${p.id}'),
          product: p,
          query: typed,
          onTap: () => context.push(AppRoutes.product(_shell, p.id)),
        ),
      );
    }
    return rows;
  }

  Widget _resultsBody(BuildContext context) {
    final query = _query;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (query != null) _toolbar(context, query),
        Expanded(child: _results(context)),
      ],
    );
  }

  Widget _toolbar(BuildContext context, BrowseQuery q) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final filters = q.activeFilterCount;
    final scope = _scope;
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
              if (scope != null) ...[
                const SizedBox(width: 8),
                KChip(
                  key: const Key('chip-scope'),
                  label: scope.name.of(lang),
                  icon: KIcons.close,
                  selected: true,
                  onTap: _dropScope,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _results(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final query = _query;
    if (_failed && query != null) {
      return KEmptyState(
        icon: KIcons.error,
        title: l10n.storeLoadFailed,
        action: KButton.outline(
          label: l10n.storeRetry,
          onPressed: () => _start(query),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final rows = box.maxWidth < rowsUpTo;
        if (_loading || query == null) {
          return ListView(
            padding: EdgeInsets.all(rows ? 0 : 16),
            children: [
              if (rows)
                for (var i = 0; i < 5; i++) const SearchRowSkeleton()
              else
                StoreProductGrid(
                  children: [
                    for (var i = 0; i < 6; i++) const ProductCardSkeleton(),
                  ],
                ),
            ],
          );
        }
        if (_items.isEmpty) return _empty(context, query);

        final scope = _scope;
        final countLine = Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Text.rich(
            key: const Key('result-count'),
            TextSpan(
              style: k.text.small.copyWith(color: k.colors.ink2),
              children: [
                TextSpan(
                  text: l10n.storeResultCount(_last.total),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: ' ${l10n.storeResultsFor(query.search ?? '')}'),
                if (scope != null)
                  TextSpan(
                    text: ' ${l10n.storeInCategory(scope.name.of(lang))}',
                  ),
              ],
            ),
          ),
        );
        final more = _hasMore
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: _loadingMore
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: KSpinner(blue: true),
                        )
                      : KButton.ghost(
                          key: const Key('show-more'),
                          label: l10n.storeShowMoreResults(
                            _last.total - _items.length,
                          ),
                          onPressed: _loadMore,
                        ),
                ),
              )
            : const SizedBox(height: 16);
        return ListView(
          key: const Key('search-results'),
          children: [
            countLine,
            if (rows)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: k.colors.surface,
                  border: Border.symmetric(
                    horizontal: BorderSide(color: k.colors.line),
                  ),
                ),
                child: Column(
                  children: [
                    for (final (i, item) in _items.indexed) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          thickness: 1,
                          indent: 92,
                          color: k.colors.line,
                        ),
                      SearchResultRow(
                        key: ValueKey(item.id),
                        item: item,
                        role: widget.role,
                      ),
                    ],
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: StoreProductGrid(
                  children: [
                    for (final item in _items)
                      StoreProductCard(
                        key: ValueKey(item.id),
                        item: item,
                        role: widget.role,
                      ),
                  ],
                ),
              ),
            more,
          ],
        );
      },
    );
  }

  /// C-04b, or "no matches" with Clear filters when filters emptied it.
  Widget _empty(BuildContext context, BrowseQuery query) {
    final l10n = AppLocalizations.of(context);
    if (query.activeFilterCount > 0) {
      return ListView(
        children: [
          KEmptyState(
            icon: KIcons.filter,
            title: l10n.storeNoMatches,
            message: l10n.storeNoMatchesBody,
            action: KButton.outline(
              key: const Key('clear-filters'),
              label: l10n.storeClearFilters,
              onPressed: () => _update(query.cleared()),
            ),
          ),
        ],
      );
    }
    final popular = ref.watch(popularCategoriesProvider).value ?? const [];
    final better = _didYouMean;
    return ListView(
      key: const Key('search-empty'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Semantics(
          liveRegion: true,
          child: KEmptyState(
            icon: KIcons.search,
            title: l10n.storeNoResultsFor(query.search ?? ''),
            action: better == null
                ? null
                : DidYouMean(suggestion: better, onTap: () => _submit(better)),
          ),
        ),
        const SearchTipsCard(),
        if (popular.isNotEmpty) ...[
          const SizedBox(height: 16),
          SearchSectionHead(title: l10n.storePopularCategories),
          CategoryChips(categories: popular, shell: _shell),
        ],
      ],
    );
  }
}

/// The 64 px search header with a bottom line, sized to the store width.
class _SearchBar extends StatelessWidget implements PreferredSizeWidget {
  const _SearchBar({required this.child});

  final Widget child;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final c = context.k.colors;
    return Material(
      color: c.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.line)),
          ),
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: storeMaxWidth),
            child: child,
          ),
        ),
      ),
    );
  }
}
