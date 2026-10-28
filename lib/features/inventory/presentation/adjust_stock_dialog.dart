import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/k_ui.dart';
import '../../admin/presentation/admin_providers.dart';
import '../../admin/presentation/admin_shell.dart';
import '../../catalog/presentation/catalog_providers.dart';
import '../../catalog/presentation/product_thumb.dart';
import '../data/inventory_repository.dart';
import '../domain/inventory.dart';
import 'inventory_labels.dart';
import 'inventory_providers.dart';

/// A-06a over the inventory list: a 560 px modal on desktop, a sheet on
/// phones. Closes after a saved adjustment and refreshes what shows stock.
Future<void> openAdjustStock(BuildContext context, InventoryRow row) async {
  if (!isAdminWide(context)) {
    await showKBottomSheet<void>(
      context,
      title: AppLocalizations.of(context).inventoryAdjustTitle,
      builder: (_) => SingleChildScrollView(child: AdjustStockForm(row: row)),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    barrierColor: KColors.scrim,
    builder: (_) => _AdjustDialog(row: row),
  );
}

/// The k-ui `.modal` around the form: title bar with close, scrolling body.
class _AdjustDialog extends StatelessWidget {
  const _AdjustDialog({required this.row});

  final InventoryRow row;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    return Dialog(
      backgroundColor: k.colors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KRadius.dialog),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: k.colors.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        l10n.inventoryAdjustTitle,
                        style: k.text.h3.copyWith(
                          fontSize: 18,
                          height: 26 / 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  KIconButton(
                    icon: KIcons.close,
                    label: l10n.uiClose,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: AdjustStockForm(row: row),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdjustStockForm extends ConsumerStatefulWidget {
  const AdjustStockForm({super.key, required this.row});

  final InventoryRow row;

  @override
  ConsumerState<AdjustStockForm> createState() => _AdjustStockFormState();
}

class _AdjustStockFormState extends ConsumerState<AdjustStockForm> {
  var _mode = AdjustMode.add;
  var _reason = AdjustReason.defaultFor(AdjustMode.add);
  final _qty = TextEditingController();
  final _note = TextEditingController();
  var _saving = false;
  String? _error;

  InventoryRow get row => widget.row;
  int? get _qtyValue => int.tryParse(_qty.text.trim());

  AdjustProblem? get _problem => adjustProblem(
    mode: _mode,
    onHand: row.onHand,
    reserved: row.reserved,
    qty: _qtyValue,
  );

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  void _setMode(AdjustMode mode) => setState(() {
    _mode = mode;
    if (!_reason.modes.contains(mode)) _reason = AdjustReason.defaultFor(mode);
    _error = null;
  });

  String? _qtyError(AppLocalizations l10n) {
    if (_qty.text.trim().isEmpty) return null;
    return switch (_problem) {
      null => null,
      AdjustProblem.qtyRequired => l10n.inventoryErrQty,
      AdjustProblem.qtyTooLarge => l10n.inventoryErrTooLarge,
      AdjustProblem.belowReserved => l10n.inventoryErrBelowReserved(
        row.reserved,
      ),
      AdjustProblem.noChange => l10n.inventoryErrNoChange,
    };
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final qty = _qtyValue;
    if (_problem != null || qty == null) return;
    final after = onHandAfter(_mode, row.onHand, qty)!;
    final label = reasonLabel(l10n, _reason);

    final ok = await showKConfirm(
      context,
      title: l10n.inventoryConfirmTitle,
      message: l10n.inventoryConfirmBody(row.sku, row.onHand, after, label),
      confirmLabel: l10n.inventorySave,
      cancelLabel: l10n.uiCancel,
      icon: KIcons.stock,
    );
    if (!ok || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    final outcome = await ref
        .read(inventoryRepositoryProvider)
        .adjust(
          StockAdjustment(
            variantId: row.variantId,
            mode: _mode,
            qty: qty,
            reason: _reason,
            note: _note.text,
          ),
          reasonLabel: label,
        );
    if (!mounted) return;

    if (outcome is StockAdjusted) {
      ref
        ..invalidate(inventoryPageProvider)
        ..invalidate(stockHistoryProvider)
        ..invalidate(catalogPageProvider)
        ..invalidate(adminBadgesProvider);
      showKToast(
        context,
        message: l10n.inventorySaved(row.sku, outcome.onHand),
        tone: KToastTone.ok,
        icon: KIcons.success,
      );
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _error = outcomeMessage(l10n, outcome);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final lang = Localizations.localeOf(context).languageCode;
    final variant = row.variantLabel;
    final (pillLabel, pillTone) = statePill(l10n, row.state);
    final after = onHandAfter(_mode, row.onHand, _qtyValue);
    final canSave = _problem == null && !_saving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            ProductThumb(url: row.mainImageUrl, size: 48),
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
                  ),
                  Text(
                    l10n.inventoryItemSub(row.sku, row.onHand, row.reserved),
                    style: k.text.caption.copyWith(color: k.colors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            KStatusPill(label: pillLabel, tone: pillTone),
          ],
        ),
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text(l10n.inventoryAdjustment, style: k.text.label),
        ),
        const SizedBox(height: 8),
        for (final mode in AdjustMode.values) ...[
          KOptionTile(
            title: modeLabel(l10n, mode),
            subtitle: modeHelp(l10n, mode),
            selected: _mode == mode,
            onTap: () => _setMode(mode),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        KTextField(
          label: qtyLabel(l10n, _mode),
          controller: _qty,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          suffix: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              l10n.inventoryUnits,
              style: k.text.small.copyWith(color: k.colors.muted),
            ),
          ),
          errorText: _qtyError(l10n),
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 16),
        Text(l10n.inventoryReason, style: k.text.label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final reason in AdjustReason.forMode(_mode))
              KChip(
                label: reasonLabel(l10n, reason),
                selected: _reason == reason,
                onTap: () => setState(() => _reason = reason),
              ),
          ],
        ),
        const SizedBox(height: 16),
        KTextField(
          label: l10n.inventoryNote,
          optional: true,
          controller: _note,
          hint: l10n.inventoryNoteHint,
          maxLines: 2,
          maxLength: maxAdjustNote,
        ),
        const SizedBox(height: 16),
        _Preview(
          onHand: row.onHand,
          after: after,
          reserved: row.reserved,
          alertAt: row.alertAt,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.inventoryAuditHelp,
          style: k.text.caption.copyWith(color: k.colors.muted),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          KBanner(message: _error!, tone: KBannerTone.bad, icon: KIcons.error),
        ],
        const SizedBox(height: 16),
        _Recent(variantId: row.variantId),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 8,
          children: [
            KButton.outline(
              label: l10n.uiCancel,
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
            ),
            KButton(
              label: l10n.inventorySave,
              loading: _saving,
              onPressed: canSave ? _save : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// "On hand after saving 4 → 54 OK": the count and the state it leads to.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.onHand,
    required this.after,
    required this.reserved,
    required this.alertAt,
  });

  final int onHand;
  final int? after;
  final int reserved;
  final int alertAt;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final after = this.after;
    final state = after == null
        ? null
        : InventoryState.of(available: after - reserved, alertAt: alertAt);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: k.colors.tint,
          border: Border.all(color: k.colors.tintLine),
          borderRadius: BorderRadius.circular(KRadius.input),
        ),
        child: Row(
          children: [
            Expanded(child: Text(l10n.inventoryAfter, style: k.text.small)),
            Text(
              '$onHand',
              style: k.text.small.copyWith(color: k.colors.muted),
            ),
            const SizedBox(width: 8),
            ExcludeSemantics(
              child: Text(
                '→',
                style: k.text.small.copyWith(color: k.colors.muted),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              after == null ? '–' : '$after',
              style: k.text.title.copyWith(
                fontSize: 18,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (state != null) ...[
              const SizedBox(width: 8),
              Builder(
                builder: (context) {
                  final (label, tone) = statePill(l10n, state);
                  return KStatusPill(label: label, tone: tone);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The last few movements of this variant.
class _Recent extends ConsumerWidget {
  const _Recent({required this.variantId});

  final String variantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final history = ref.watch(stockHistoryProvider(variantId)).value;
    if (history == null || history.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.inventoryRecent, style: k.text.label),
        const SizedBox(height: 4),
        for (final m in history.take(5))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    [
                      changeLabel(l10n, m.reason, m.delta),
                      if (m.note != null) m.note!,
                    ].join(' · '),
                    style: k.text.small,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  whoLabel(
                    l10n,
                    at: m.at,
                    actor: m.actor,
                    orderNumber: m.orderNumber,
                  ),
                  style: k.text.caption.copyWith(color: k.colors.muted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// "Adjust stock" from the page head: search for the SKU first.
Future<InventoryRow?> pickInventoryRow(BuildContext context) =>
    showKBottomSheet<InventoryRow>(
      context,
      title: AppLocalizations.of(context).inventoryPickTitle,
      builder: (_) => const _RowPicker(),
    );

class _RowPicker extends ConsumerStatefulWidget {
  const _RowPicker();

  @override
  ConsumerState<_RowPicker> createState() => _RowPickerState();
}

class _RowPickerState extends ConsumerState<_RowPicker> {
  Timer? _debounce;
  late Future<InventoryPage> _results = _load('');

  Future<InventoryPage> _load(String search) => ref
      .read(inventoryRepositoryProvider)
      .list(InventoryQuery(filter: InventoryFilter.all, search: search));

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final lang = Localizations.localeOf(context).languageCode;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KTextField.search(
          hint: l10n.inventorySearchHint,
          onChanged: (text) {
            _debounce?.cancel();
            _debounce = Timer(
              const Duration(milliseconds: 350),
              () => setState(() => _results = _load(text)),
            );
          },
        ),
        const SizedBox(height: 12),
        Flexible(
          child: FutureBuilder<InventoryPage>(
            future: _results,
            builder: (context, snap) {
              final rows = snap.data?.rows;
              if (rows == null) {
                return snap.hasError
                    ? Text(l10n.inventoryLoadFailed, style: k.text.small)
                    : const Center(child: KSpinner());
              }
              if (rows.isEmpty) {
                return Text(
                  l10n.inventoryEmptyBody,
                  style: k.text.small.copyWith(color: k.colors.muted),
                );
              }
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final row in rows)
                      KListRow(
                        leading: ProductThumb(url: row.mainImageUrl, size: 40),
                        title: [
                          row.name.of(lang),
                          if (row.variantLabel.isNotEmpty) row.variantLabel,
                        ].join(' · '),
                        subtitle: l10n.inventoryItemSub(
                          row.sku,
                          row.onHand,
                          row.reserved,
                        ),
                        onTap: () => Navigator.of(context).pop(row),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
