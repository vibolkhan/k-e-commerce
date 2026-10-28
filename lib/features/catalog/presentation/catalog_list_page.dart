import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/time/date_format.dart';
import '../../../core/ui/k_ui.dart';
import '../../admin/presentation/admin_shell.dart';
import '../data/catalog_repository.dart';
import '../domain/catalog_list.dart';
import '../domain/catalog_outcome.dart';
import 'catalog_labels.dart';
import 'catalog_providers.dart';
import 'category_picker.dart';
import 'import_wizard.dart';
import 'product_thumb.dart';

/// A-05 Products: status tabs, search, filters, bulk archive / move.
class CatalogListPage extends ConsumerStatefulWidget {
  const CatalogListPage({super.key});

  @override
  ConsumerState<CatalogListPage> createState() => _CatalogListPageState();
}

class _CatalogListPageState extends ConsumerState<CatalogListPage> {
  final _selected = <String>{};
  Timer? _debounce;
  late final _search = TextEditingController(
    text: ref.read(catalogQueryProvider).search,
  );

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _query(CatalogListQuery Function(CatalogListQuery) change) {
    setState(_selected.clear);
    ref.read(catalogQueryProvider.notifier).update(change);
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _query((q) => q.copyWith(search: text)),
    );
  }

  Future<void> _archiveSelected() async {
    final l10n = AppLocalizations.of(context);
    final ids = _selected.toList();
    final ok = await showKConfirm(
      context,
      title: l10n.catalogArchiveManyTitle(ids.length),
      message: l10n.catalogArchiveManyBody,
      confirmLabel: l10n.catalogArchiveManyConfirm,
      cancelLabel: l10n.uiCancel,
      tone: KConfirmTone.destructive,
      icon: KIcons.delete,
    );
    if (!ok || !mounted) return;
    final outcome = await ref.read(catalogRepositoryProvider).archiveMany(ids);
    if (!mounted) return;
    _toast(
      outcome,
      outcome is CatalogUpdated ? l10n.catalogArchivedMany(outcome.count) : '',
    );
  }

  Future<void> _moveSelected() async {
    final l10n = AppLocalizations.of(context);
    final category = await pickCategory(context, ref);
    if (category == null || !mounted) return;
    final ids = _selected.toList();
    final outcome = await ref
        .read(catalogRepositoryProvider)
        .moveMany(ids, category.id);
    if (!mounted) return;
    final name = category.name.of(Localizations.localeOf(context).languageCode);
    _toast(
      outcome,
      outcome is CatalogUpdated
          ? l10n.catalogMovedMany(outcome.count, name)
          : '',
    );
  }

  void _toast(CatalogOutcome outcome, String done) {
    final ok = outcome is CatalogUpdated;
    showKToast(
      context,
      message: ok
          ? done
          : outcomeMessage(AppLocalizations.of(context), outcome),
      tone: ok ? KToastTone.ok : KToastTone.bad,
      icon: ok ? KIcons.success : KIcons.error,
    );
    if (ok) {
      setState(_selected.clear);
      ref.invalidate(catalogPageProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canEdit = ref.watch(canEditCatalogProvider);
    final query = ref.watch(catalogQueryProvider);
    final page = ref.watch(catalogPageProvider);
    final counts = page.value?.counts ?? const {};
    final wide = isAdminWide(context);

    return AdminPage(
      title: l10n.adminSectionCatalog,
      actions: [
        if (canEdit) ...[
          KButton.outline(
            label: l10n.catalogImport,
            icon: KIcons.upload,
            size: KButtonSize.sm,
            onPressed: () => openImportWizard(context),
          ),
          KButton(
            label: l10n.catalogAdd,
            icon: KIcons.plus,
            size: KButtonSize.sm,
            onPressed: () => context.go(AppRoutes.adminProductNew),
          ),
        ],
      ],
      children: [
        if (!canEdit) ...[
          KBanner(message: l10n.catalogReadOnly, icon: KIcons.info),
          const SizedBox(height: 16),
        ],
        KTabs(
          tabs: [
            for (final tab in CatalogTab.values)
              KTab(tabLabel(l10n, tab), count: counts[tab]),
          ],
          selectedIndex: query.tab.index,
          onChanged: (i) =>
              _query((q) => q.copyWith(tab: CatalogTab.values[i])),
        ),
        const SizedBox(height: 16),
        _Filters(
          search: _search,
          onSearch: _onSearch,
          query: query,
          onQuery: _query,
        ),
        const SizedBox(height: 16),
        if (canEdit && _selected.isNotEmpty) ...[
          _BulkBar(
            count: _selected.length,
            onArchive: query.tab == CatalogTab.archived
                ? null
                : _archiveSelected,
            onMove: _moveSelected,
          ),
          const SizedBox(height: 12),
        ],
        switch (page) {
          AsyncValue(:final value?)
              when !page.isLoading || value.rows.isNotEmpty =>
            _Results(
              page: value,
              query: query,
              wide: wide,
              canEdit: canEdit,
              selected: _selected,
              onSelect: (id, on) =>
                  setState(() => on ? _selected.add(id) : _selected.remove(id)),
              onSelectAll: (on) => setState(() {
                on
                    ? _selected.addAll(value.rows.map((r) => r.id))
                    : _selected.clear();
              }),
              onPage: (p) => _query((q) => q.copyWith(page: p)),
              onClear: () {
                _search.clear();
                setState(_selected.clear);
                ref.read(catalogQueryProvider.notifier).clearFilters();
              },
            ),
          AsyncValue(hasError: true) => KEmptyState(
            icon: KIcons.error,
            title: l10n.catalogLoadFailed,
            action: KButton.outline(
              label: l10n.catalogRetry,
              onPressed: () => ref.invalidate(catalogPageProvider),
            ),
          ),
          _ => const _Loading(),
        },
      ],
    );
  }
}

class _Filters extends ConsumerWidget {
  const _Filters({
    required this.search,
    required this.onSearch,
    required this.query,
    required this.onQuery,
  });

  final TextEditingController search;
  final ValueChanged<String> onSearch;
  final CatalogListQuery query;
  final void Function(CatalogListQuery Function(CatalogListQuery)) onQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final categories = ref.watch(catalogCategoriesProvider).value ?? const [];
    final category = categories.where((c) => c.id == query.categoryId);
    final categoryName = category.isEmpty
        ? l10n.catalogAllCategories
        : category.first.name.of(lang);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: KTextField.search(
            controller: search,
            hint: l10n.catalogSearchHint,
            onChanged: onSearch,
            onSubmitted: onSearch,
          ),
        ),
        KChip(
          label: '${l10n.catalogFilterCategory}: $categoryName',
          icon: KIcons.chevronDown,
          selected: query.categoryId != null,
          onTap: () async {
            final picked = await pickCategory(context, ref, allowAll: true);
            if (picked == null) return;
            onQuery(
              (q) => q.copyWith(
                categoryId: () => picked.id.isEmpty ? null : picked.id,
              ),
            );
          },
        ),
        for (final filter in StockFilter.values.skip(1))
          KChip(
            label: stockFilterLabel(l10n, filter),
            selected: query.stock == filter,
            onTap: () => onQuery(
              (q) => q.copyWith(
                stock: query.stock == filter ? StockFilter.any : filter,
              ),
            ),
          ),
        KChip(
          label: l10n.catalogQuoteEnabled,
          icon: KIcons.quote,
          selected: query.quoteOnly,
          onTap: () => onQuery((q) => q.copyWith(quoteOnly: !q.quoteOnly)),
        ),
      ],
    );
  }
}

class _BulkBar extends StatelessWidget {
  const _BulkBar({
    required this.count,
    required this.onArchive,
    required this.onMove,
  });

  final int count;
  final VoidCallback? onArchive;
  final VoidCallback onMove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: k.colors.tint,
        border: Border.all(color: k.colors.tintLine),
        borderRadius: BorderRadius.circular(KRadius.input),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              l10n.catalogSelected(count),
              style: k.text.label.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (onArchive != null)
            KButton(
              label: l10n.catalogArchive,
              variant: KButtonVariant.dangerOutline,
              size: KButtonSize.sm,
              onPressed: onArchive,
            ),
          KButton.outline(
            label: l10n.catalogChangeCategory,
            size: KButtonSize.sm,
            onPressed: onMove,
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.page,
    required this.query,
    required this.wide,
    required this.canEdit,
    required this.selected,
    required this.onSelect,
    required this.onSelectAll,
    required this.onPage,
    required this.onClear,
  });

  final CatalogPage page;
  final CatalogListQuery query;
  final bool wide;
  final bool canEdit;
  final Set<String> selected;
  final void Function(String id, bool on) onSelect;
  final ValueChanged<bool> onSelectAll;
  final ValueChanged<int> onPage;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    if (page.rows.isEmpty) {
      return KEmptyState(
        icon: KIcons.package,
        title: l10n.catalogEmptyTitle,
        message: l10n.catalogEmptyBody,
        action: KButton.outline(
          label: l10n.catalogClearFilters,
          onPressed: onClear,
        ),
      );
    }
    final first = query.page * CatalogListQuery.pageSize;
    final last = first + page.rows.length;
    final lastPage = (page.total - 1) ~/ CatalogListQuery.pageSize;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.catalogShowing(page.rows.length, page.total),
          style: k.text.caption.copyWith(color: k.colors.muted),
        ),
        const SizedBox(height: 8),
        if (wide)
          _Table(
            rows: page.rows,
            canEdit: canEdit,
            selected: selected,
            onSelect: onSelect,
            onSelectAll: onSelectAll,
          )
        else
          for (final row in page.rows) ...[
            _Card(
              item: row,
              canEdit: canEdit,
              selected: selected.contains(row.id),
              onSelect: (on) => onSelect(row.id, on),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              l10n.catalogRange(first + 1, last, page.total),
              style: k.text.caption.copyWith(color: k.colors.muted),
            ),
            const SizedBox(width: 8),
            KIconButton(
              icon: KIcons.back,
              label: l10n.catalogPrev,
              style: KIconButtonStyle.outline,
              onPressed: query.page > 0 ? () => onPage(query.page - 1) : null,
            ),
            const SizedBox(width: 8),
            KIconButton(
              icon: KIcons.chevronRight,
              label: l10n.catalogNext,
              style: KIconButtonStyle.outline,
              onPressed: query.page < lastPage
                  ? () => onPage(query.page + 1)
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Desktop: the A-05 table.
class _Table extends StatelessWidget {
  const _Table({
    required this.rows,
    required this.canEdit,
    required this.selected,
    required this.onSelect,
    required this.onSelectAll,
  });

  final List<CatalogListItem> rows;
  final bool canEdit;
  final Set<String> selected;
  final void Function(String id, bool on) onSelect;
  final ValueChanged<bool> onSelectAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final lang = Localizations.localeOf(context).languageCode;
    final head = k.text.caption.copyWith(
      color: k.colors.muted,
      fontWeight: FontWeight.w700,
    );
    Widget cell(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: child,
    );
    Widget th(String text) => cell(Text(text, style: head));
    final allOn = rows.every((r) => selected.contains(r.id));

    return Container(
      decoration: BoxDecoration(
        color: k.colors.surface,
        border: Border.all(color: k.colors.line),
        borderRadius: BorderRadius.circular(KRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: {
          if (canEdit) 0: const FixedColumnWidth(52),
          for (var i = canEdit ? 1 : 0; i < (canEdit ? 10 : 9); i++)
            i: i == (canEdit ? 1 : 0)
                ? const FlexColumnWidth(3)
                : const FlexColumnWidth(),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: k.colors.soft,
              border: Border(bottom: BorderSide(color: k.colors.line)),
            ),
            children: [
              if (canEdit)
                cell(
                  Checkbox(
                    value: allOn,
                    semanticLabel: l10n.catalogSelectAll,
                    onChanged: (on) => onSelectAll(on ?? false),
                  ),
                ),
              th(l10n.catalogColProduct),
              th(l10n.catalogColCategory),
              th(l10n.catalogColVariants),
              th(l10n.catalogColPrice),
              th(l10n.catalogColStock),
              th(l10n.catalogColQuotes),
              th(l10n.catalogColStatus),
              th(l10n.catalogColUpdated),
              const SizedBox.shrink(),
            ],
          ),
          for (final row in rows)
            TableRow(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: k.colors.line)),
              ),
              children: [
                if (canEdit)
                  cell(
                    Checkbox(
                      value: selected.contains(row.id),
                      semanticLabel: l10n.catalogSelectRow(row.name.of(lang)),
                      onChanged: (on) => onSelect(row.id, on ?? false),
                    ),
                  ),
                cell(_ProductCell(item: row)),
                cell(Text(row.category.of(lang), style: k.text.small)),
                cell(Text('${row.variantCount}', style: k.text.small)),
                cell(
                  Text(
                    priceRange(l10n, row.minPriceCents, row.maxPriceCents),
                    style: k.text.small.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                cell(
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _StockPill(row),
                  ),
                ),
                cell(
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _QuotePill(row),
                  ),
                ),
                cell(
                  Align(
                    alignment: Alignment.centerLeft,
                    child: KStatusPill(
                      label: statusLabel(l10n, row.status),
                      tone: statusTone(row.status),
                      dot: true,
                    ),
                  ),
                ),
                cell(_Updated(row)),
                cell(
                  KButton.ghost(
                    label: canEdit ? l10n.catalogEdit : l10n.catalogView,
                    size: KButtonSize.sm,
                    onPressed: () => context.go(AppRoutes.adminProduct(row.id)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Phone: one card per product.
class _Card extends StatelessWidget {
  const _Card({
    required this.item,
    required this.canEdit,
    required this.selected,
    required this.onSelect,
  });

  final CatalogListItem item;
  final bool canEdit;
  final bool selected;
  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final lang = Localizations.localeOf(context).languageCode;
    return KCard(
      onTap: () => context.go(AppRoutes.adminProduct(item.id)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canEdit)
            Checkbox(
              value: selected,
              semanticLabel: l10n.catalogSelectRow(item.name.of(lang)),
              onChanged: (on) => onSelect(on ?? false),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProductCell(item: item),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      priceRange(l10n, item.minPriceCents, item.maxPriceCents),
                      style: k.text.label.copyWith(fontWeight: FontWeight.w800),
                    ),
                    KStatusPill(
                      label: statusLabel(l10n, item.status),
                      tone: statusTone(item.status),
                      dot: true,
                    ),
                    _StockPill(item),
                    if (item.rfqEnabled) _QuotePill(item),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCell extends StatelessWidget {
  const _ProductCell({required this.item});

  final CatalogListItem item;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final lang = Localizations.localeOf(context).languageCode;
    final sub = [
      if (item.firstSku != null) item.firstSku!,
      if (item.brand != null) item.brand!,
    ].join(' · ');
    return Row(
      children: [
        ProductThumb(url: item.mainImageUrl, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name.of(lang),
                style: k.text.label.copyWith(fontWeight: FontWeight.w700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (sub.isNotEmpty)
                Text(
                  sub,
                  style: k.text.caption.copyWith(color: k.colors.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StockPill extends StatelessWidget {
  const _StockPill(this.item);
  final CatalogListItem item;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = stockPill(AppLocalizations.of(context), item);
    return KStatusPill(label: label, tone: tone);
  }
}

class _QuotePill extends StatelessWidget {
  const _QuotePill(this.item);
  final CatalogListItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return item.rfqEnabled && item.rfqMinQty != null
        ? KStatusPill(
            label: l10n.catalogQuoteMin(item.rfqMinQty!),
            tone: KTone.violet,
          )
        : KStatusPill(label: l10n.catalogQuoteOff, tone: KTone.gray);
  }
}

class _Updated extends StatelessWidget {
  const _Updated(this.item);
  final CatalogListItem item;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final at = item.updatedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (at != null)
          Text(
            formatDayMonth(AppLocalizations.of(context), at),
            style: k.text.small,
          ),
        if (item.updatedBy != null)
          Text(
            item.updatedBy!,
            style: k.text.caption.copyWith(color: k.colors.muted),
          ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < 6; i++)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: KSkeleton(height: 44),
        ),
    ],
  );
}
