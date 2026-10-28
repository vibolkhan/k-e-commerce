import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/money_format.dart';
import '../../../core/ui/k_ui.dart';
import '../../admin/presentation/admin_shell.dart';
import '../../admin/presentation/admin_stat_tile.dart';
import '../../catalog/presentation/product_thumb.dart';
import '../domain/inventory.dart';
import 'adjust_stock_dialog.dart';
import 'inventory_labels.dart';
import 'inventory_providers.dart';
import 'stock_history_sheet.dart';

/// A-06 Inventory: summary tiles, restock / out / all filters, the stock
/// table, and Adjust (A-06a) for catalog staff.
class InventoryListPage extends ConsumerStatefulWidget {
  const InventoryListPage({super.key});

  @override
  ConsumerState<InventoryListPage> createState() => _InventoryListPageState();
}

class _InventoryListPageState extends ConsumerState<InventoryListPage> {
  Timer? _debounce;
  late final _search = TextEditingController(
    text: ref.read(inventoryQueryProvider).search,
  );

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _query(InventoryQuery Function(InventoryQuery) change) =>
      ref.read(inventoryQueryProvider.notifier).update(change);

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _query((q) => q.copyWith(search: text)),
    );
  }

  Future<void> _adjustAny() async {
    final row = await pickInventoryRow(context);
    if (row == null || !mounted) return;
    await openAdjustStock(context, row);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final canAdjust = ref.watch(canAdjustStockProvider);
    final query = ref.watch(inventoryQueryProvider);
    final page = ref.watch(inventoryPageProvider);
    final value = page.value;

    return AdminPage(
      title: l10n.adminSectionInventory,
      actions: [
        Tooltip(
          message: l10n.inventoryExportSoon,
          child: KButton.outline(
            label: l10n.inventoryExport,
            icon: KIcons.reports,
            size: KButtonSize.sm,
            onPressed: null,
          ),
        ),
        if (canAdjust)
          KButton(
            label: l10n.inventoryAdjust,
            icon: KIcons.plus,
            size: KButtonSize.sm,
            onPressed: _adjustAny,
          ),
      ],
      children: [
        Text(
          l10n.inventoryBreadcrumb,
          style: k.text.small.copyWith(color: k.colors.muted),
        ),
        const SizedBox(height: 16),
        if (!canAdjust) ...[
          KBanner(message: l10n.inventoryReadOnly, icon: KIcons.info),
          const SizedBox(height: 16),
        ],
        _Tiles(summary: value?.summary),
        const SizedBox(height: 16),
        _Toolbar(
          search: _search,
          onSearch: _onSearch,
          query: query,
          counts: value?.counts ?? const {},
          onFilter: (f) => _query((q) => q.copyWith(filter: f)),
        ),
        const SizedBox(height: 16),
        switch (page) {
          AsyncValue(:final value?)
              when !page.isLoading || value.rows.isNotEmpty =>
            _Results(
              page: value,
              query: query,
              canAdjust: canAdjust,
              onPage: (p) => _query((q) => q.copyWith(page: p)),
              onShowAll: () {
                _search.clear();
                _query(
                  (q) => q.copyWith(filter: InventoryFilter.all, search: ''),
                );
              },
            ),
          AsyncValue(hasError: true) => KEmptyState(
            icon: KIcons.error,
            title: l10n.inventoryLoadFailed,
            action: KButton.outline(
              label: l10n.catalogRetry,
              onPressed: () => ref.invalidate(inventoryPageProvider),
            ),
          ),
          _ => const _Loading(),
        },
      ],
    );
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.summary});

  final InventorySummary? summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final s = summary;
    String number(int? n) => n == null ? '–' : '$n';
    return AdminStatRow(
      tiles: [
        AdminStatTile(
          label: l10n.inventoryTileLow,
          value: number(s?.low),
          footnote: l10n.inventoryTileLowFoot,
          valueColor: (s?.low ?? 0) > 0 ? k.colors.warn : null,
        ),
        AdminStatTile(
          label: l10n.inventoryTileOut,
          value: number(s?.out),
          footnote: l10n.inventoryTileOutFoot,
          valueColor: (s?.out ?? 0) > 0 ? k.colors.bad : null,
        ),
        AdminStatTile(
          label: l10n.inventoryTileReserved,
          value: number(s?.reservedUnits),
          footnote: l10n.inventoryTileReservedFoot,
        ),
        AdminStatTile(
          label: l10n.inventoryTileValue,
          value: s == null ? '–' : formatUsdWhole(s.stockValueCents),
          footnote: l10n.inventoryTileValueFoot,
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.search,
    required this.onSearch,
    required this.query,
    required this.counts,
    required this.onFilter,
  });

  final TextEditingController search;
  final ValueChanged<String> onSearch;
  final InventoryQuery query;
  final Map<InventoryFilter, int> counts;
  final ValueChanged<InventoryFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: KTextField.search(
            controller: search,
            hint: l10n.inventorySearchHint,
            onChanged: onSearch,
            onSubmitted: onSearch,
          ),
        ),
        Semantics(
          container: true,
          label: l10n.inventoryFilterLabel,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final filter in InventoryFilter.values)
                KChip(
                  label: filterLabel(l10n, filter),
                  count: filter == InventoryFilter.all ? null : counts[filter],
                  selected: query.filter == filter,
                  onTap: () => onFilter(filter),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            l10n.inventoryHoldNote,
            style: k.text.caption.copyWith(color: k.colors.muted),
          ),
        ),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.page,
    required this.query,
    required this.canAdjust,
    required this.onPage,
    required this.onShowAll,
  });

  final InventoryPage page;
  final InventoryQuery query;
  final bool canAdjust;
  final ValueChanged<int> onPage;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    if (page.rows.isEmpty) {
      final restockOnly =
          query.filter == InventoryFilter.restock && query.search.isEmpty;
      return KEmptyState(
        icon: KIcons.stock,
        title: l10n.inventoryEmptyTitle,
        message: restockOnly
            ? l10n.inventoryEmptyRestock
            : l10n.inventoryEmptyBody,
        action: query.filter == InventoryFilter.all && query.search.isEmpty
            ? null
            : KButton.outline(
                label: l10n.inventoryShowAll,
                onPressed: onShowAll,
              ),
      );
    }
    final first = query.page * InventoryQuery.pageSize;
    final last = first + page.rows.length;
    final lastPage = (page.total - 1) ~/ InventoryQuery.pageSize;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isAdminWide(context))
          _Table(rows: page.rows, canAdjust: canAdjust)
        else
          for (final row in page.rows) ...[
            _Card(row: row, canAdjust: canAdjust),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Text(
                  l10n.inventoryFooter(
                    page.counts[InventoryFilter.restock] ?? 0,
                  ),
                  style: k.text.caption.copyWith(color: k.colors.muted),
                ),
                KButton.ghost(
                  label: l10n.inventoryViewHistory,
                  size: KButtonSize.sm,
                  onPressed: () => showStockHistory(context),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
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
                  onPressed: query.page > 0
                      ? () => onPage(query.page - 1)
                      : null,
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
        ),
      ],
    );
  }
}

/// Desktop: the A-06 table.
class _Table extends StatelessWidget {
  const _Table({required this.rows, required this.canAdjust});

  final List<InventoryRow> rows;
  final bool canAdjust;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final head = k.text.caption.copyWith(
      color: k.colors.muted,
      fontWeight: FontWeight.w700,
    );
    final number = k.text.small.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget cell(Widget child, {bool end = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Align(
        alignment: end ? Alignment.centerRight : Alignment.centerLeft,
        child: child,
      ),
    );
    Widget th(String text, {bool end = false}) =>
        cell(Text(text, style: head), end: end);

    return Container(
      decoration: BoxDecoration(
        color: k.colors.surface,
        border: Border.all(color: k.colors.line),
        borderRadius: BorderRadius.circular(KRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        // Product and last change share the room left; the rest fit.
        columnWidths: const {
          0: IntrinsicColumnWidth(),
          1: FlexColumnWidth(3),
          2: IntrinsicColumnWidth(),
          3: IntrinsicColumnWidth(),
          4: IntrinsicColumnWidth(),
          5: IntrinsicColumnWidth(),
          6: IntrinsicColumnWidth(),
          7: FlexColumnWidth(2),
          8: IntrinsicColumnWidth(),
        },
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: k.colors.soft,
              border: Border(bottom: BorderSide(color: k.colors.line)),
            ),
            children: [
              th(l10n.inventoryColSku),
              th(l10n.inventoryColProduct),
              th(l10n.inventoryColOnHand, end: true),
              th(l10n.inventoryColReserved, end: true),
              th(l10n.inventoryColAvailable, end: true),
              th(l10n.inventoryColAlertAt, end: true),
              th(l10n.inventoryColStatus),
              th(l10n.inventoryColLastChange),
              Semantics(
                label: l10n.inventoryColActions,
                child: const SizedBox.shrink(),
              ),
            ],
          ),
          for (final row in rows)
            TableRow(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: k.colors.line)),
              ),
              children: [
                cell(
                  Text(
                    row.sku,
                    style: k.text.small.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                cell(_ProductCell(row: row)),
                cell(Text('${row.onHand}', style: number), end: true),
                cell(Text('${row.reserved}', style: number), end: true),
                cell(
                  Text(
                    '${row.available}',
                    style: number.copyWith(
                      fontWeight: FontWeight.w800,
                      color: row.available <= 0 ? k.colors.bad : null,
                    ),
                  ),
                  end: true,
                ),
                cell(Text('${row.alertAt}', style: number), end: true),
                cell(_StatePill(row.state)),
                cell(_LastChange(row.last)),
                cell(
                  canAdjust ? _AdjustButton(row: row) : const SizedBox.shrink(),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Phone: one card per variant.
class _Card extends StatelessWidget {
  const _Card({required this.row, required this.canAdjust});

  final InventoryRow row;
  final bool canAdjust;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _ProductCell(row: row, showSku: true)),
              const SizedBox(width: 8),
              _StatePill(row.state),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.inventoryNumbers(row.onHand, row.reserved, row.available),
            style: k.text.small.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: _LastChange(row.last)),
              if (canAdjust) _AdjustButton(row: row),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProductCell extends StatelessWidget {
  const _ProductCell({required this.row, this.showSku = false});

  final InventoryRow row;
  final bool showSku;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final lang = Localizations.localeOf(context).languageCode;
    final variant = row.variantLabel;
    return Row(
      children: [
        ProductThumb(url: row.mainImageUrl, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  row.name.of(lang),
                  if (variant.isNotEmpty) variant,
                ].join(' · '),
                style: k.text.label.copyWith(fontWeight: FontWeight.w700),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (showSku)
                Text(
                  row.sku,
                  style: k.text.caption.copyWith(color: k.colors.muted),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill(this.state);
  final InventoryState state;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = statePill(AppLocalizations.of(context), state);
    return KStatusPill(label: label, tone: tone);
  }
}

class _LastChange extends StatelessWidget {
  const _LastChange(this.last);
  final LastChange? last;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final last = this.last;
    if (last == null) {
      return Text(
        l10n.inventoryNoChanges,
        style: k.text.caption.copyWith(color: k.colors.muted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(changeLabel(l10n, last.reason, last.delta), style: k.text.small),
        Text(
          whoLabel(
            l10n,
            at: last.at,
            actor: last.actor,
            orderNumber: last.orderNumber,
          ),
          style: k.text.caption.copyWith(color: k.colors.muted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _AdjustButton extends StatelessWidget {
  const _AdjustButton({required this.row});
  final InventoryRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.inventoryAdjustRow(row.sku),
      excludeSemantics: true,
      button: true,
      child: KButton(
        label: l10n.inventoryAdjustShort,
        variant: KButtonVariant.tonal,
        size: KButtonSize.sm,
        onPressed: () => openAdjustStock(context, row),
      ),
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
