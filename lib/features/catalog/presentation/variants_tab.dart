import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/khr_rate_provider.dart';
import '../../../core/money/money_format.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/time/date_format.dart';
import '../../../core/ui/k_ui.dart';
import '../../admin/presentation/admin_shell.dart';
import '../domain/i18n_text.dart';
import '../domain/product_draft.dart';
import 'barcode_scan_sheet.dart';
import 'catalog_labels.dart';
import 'catalog_providers.dart';
import 'editor_widgets.dart';

/// A-05b Variants & pricing: options, one row per variant with SKU,
/// barcode, USD price and its KHR preview, stock and the Sell switch;
/// business quotes; stock overview and price history.
class VariantsTab extends ConsumerStatefulWidget {
  const VariantsTab({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.issues,
    required this.readOnly,
  });

  final ProductDraft draft;
  final ValueChanged<ProductDraft> onChanged;
  final List<FieldIssue> issues;
  final bool readOnly;

  @override
  ConsumerState<VariantsTab> createState() => _VariantsTabState();
}

class _VariantsTabState extends ConsumerState<VariantsTab> {
  final _variantKeys = RowKeys();
  final _optionKeys = RowKeys();

  ProductDraft get draft => widget.draft;

  /// SKU prefix for new combinations: an existing SKU without its last part.
  String get _skuPrefix {
    for (final v in draft.variants) {
      final sku = v.sku.trim();
      final dash = sku.lastIndexOf('-');
      if (dash > 0) return sku.substring(0, dash);
    }
    return '';
  }

  void _setOptions(List<ProductOption> options) {
    widget.onChanged(
      draft.copyWith(
        options: options,
        variants: variantsForOptions(
          options,
          draft.variants,
          skuPrefix: _skuPrefix,
        ),
      ),
    );
  }

  void _setVariant(int i, VariantDraft v) => widget.onChanged(
    draft.copyWith(
      variants: [...draft.variants.take(i), v, ...draft.variants.skip(i + 1)],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ro = widget.readOnly;
    final rate = ref.watch(khrRateValueProvider);
    String? err(String field) => issueFor(l10n, widget.issues, field);

    return EditorColumns(
      main: [
        EditorCard(
          title: l10n.catalogOptions,
          subtitle: l10n.catalogOptionsSub,
          children: [
            for (var i = 0; i < draft.options.length; i++)
              _OptionEditor(
                key: ValueKey(_optionKeys.at(i, draft.options.length)),
                option: draft.options[i],
                readOnly: ro,
                error: err('options.$i.name') ?? err('options.$i.values'),
                onChanged: (o) => _setOptions([
                  ...draft.options.take(i),
                  o,
                  ...draft.options.skip(i + 1),
                ]),
                onRemove: () {
                  _optionKeys.removeAt(i);
                  _setOptions([...draft.options]..removeAt(i));
                },
              ),
            if (!ro && draft.options.length < CatalogLimits.options)
              Align(
                alignment: Alignment.centerLeft,
                child: KButton.ghost(
                  label: l10n.catalogAddOption,
                  icon: KIcons.plus,
                  size: KButtonSize.sm,
                  onPressed: () => widget.onChanged(
                    draft.copyWith(
                      options: [...draft.options, const ProductOption()],
                    ),
                  ),
                ),
              ),
          ],
        ),
        EditorCard(
          title: l10n.catalogVariants,
          subtitle: l10n.catalogPricesIncludeVat,
          children: [
            if (err('variants') case final message?)
              KBanner(message: message, tone: KBannerTone.bad),
            for (var i = 0; i < draft.variants.length; i++)
              _VariantRow(
                // Option combinations keep their row when options change.
                key: draft.variants[i].attributes.isEmpty
                    ? ValueKey(_variantKeys.at(i, draft.variants.length))
                    : ValueKey('attr:${draft.variants[i].attributes}'),
                index: i,
                variant: draft.variants[i],
                rate: rate,
                readOnly: ro,
                issues: widget.issues,
                onChanged: (v) => _setVariant(i, v),
                onRemove: draft.variants[i].isNew && draft.variants.length > 1
                    ? () {
                        _variantKeys.removeAt(i);
                        widget.onChanged(
                          draft.copyWith(
                            variants: [...draft.variants]..removeAt(i),
                          ),
                        );
                      }
                    : null,
              ),
            Text(
              l10n.catalogKhrNote(formatKhrAmount(rate)),
              style: context.k.text.caption.copyWith(
                color: context.k.colors.muted,
              ),
            ),
            if (draft.variants.any((v) => v.isNew))
              Text(
                l10n.catalogOpeningStockNote,
                style: context.k.text.caption.copyWith(
                  color: context.k.colors.muted,
                ),
              ),
            if (!ro && draft.variants.length < CatalogLimits.variants)
              Align(
                alignment: Alignment.centerLeft,
                child: KButton.ghost(
                  label: l10n.catalogAddVariant,
                  icon: KIcons.plus,
                  size: KButtonSize.sm,
                  onPressed: () => widget.onChanged(
                    draft.copyWith(
                      variants: [...draft.variants, const VariantDraft()],
                    ),
                  ),
                ),
              ),
          ],
        ),
        _QuotesCard(
          draft: draft,
          readOnly: ro,
          issues: widget.issues,
          onChanged: widget.onChanged,
        ),
      ],
      side: [
        if (draft.variants.any((v) => !v.isNew)) _StockOverview(draft: draft),
        if (draft.id case final id?) _PriceHistory(productId: id),
      ],
    );
  }
}

class _OptionEditor extends StatefulWidget {
  const _OptionEditor({
    super.key,
    required this.option,
    required this.readOnly,
    required this.error,
    required this.onChanged,
    required this.onRemove,
  });

  final ProductOption option;
  final bool readOnly;
  final String? error;
  final ValueChanged<ProductOption> onChanged;
  final VoidCallback onRemove;

  @override
  State<_OptionEditor> createState() => _OptionEditorState();
}

class _OptionEditorState extends State<_OptionEditor> {
  final _value = TextEditingController();

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _add(String text) {
    final value = text.trim();
    _value.clear();
    if (value.isEmpty || widget.option.values.contains(value)) return;
    widget.onChanged(
      widget.option.copyWith(values: [...widget.option.values, value]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final o = widget.option;
    final ro = widget.readOnly;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: context.k.colors.line),
        borderRadius: BorderRadius.circular(KRadius.input),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: KTextField(
                  label: l10n.catalogOptionName,
                  hint: l10n.catalogOptionNameHint,
                  initialValue: o.name.en,
                  readOnly: ro,
                  errorText: widget.error,
                  onChanged: (v) => widget.onChanged(
                    o.copyWith(
                      name: I18nText(en: v, km: o.name.km),
                    ),
                  ),
                ),
              ),
              if (!ro)
                KIconButton(
                  icon: KIcons.delete,
                  label: l10n.catalogRemoveOption,
                  onPressed: widget.onRemove,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final value in o.values)
                InputChip(
                  label: Text(value),
                  onDeleted: ro
                      ? null
                      : () => widget.onChanged(
                          o.copyWith(values: [...o.values]..remove(value)),
                        ),
                  deleteButtonTooltipMessage: l10n.catalogRemoveValue(value),
                ),
            ],
          ),
          if (!ro) ...[
            const SizedBox(height: 8),
            KTextField(
              controller: _value,
              hint: l10n.catalogValueHint,
              textInputAction: TextInputAction.done,
              onSubmitted: _add,
            ),
          ],
        ],
      ),
    );
  }
}

class _VariantRow extends StatelessWidget {
  const _VariantRow({
    super.key,
    required this.index,
    required this.variant,
    required this.rate,
    required this.readOnly,
    required this.issues,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final VariantDraft variant;
  final int rate;
  final bool readOnly;
  final List<FieldIssue> issues;
  final ValueChanged<VariantDraft> onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final v = variant;
    final ro = readOnly;
    String? err(String field) =>
        issueFor(l10n, issues, 'variants.$index.$field');
    final wide = isAdminWide(context);
    final price = v.priceCents;

    final sku = KTextField(
      label: l10n.catalogSku,
      initialValue: v.sku,
      readOnly: ro,
      errorText: err('sku'),
      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
      onChanged: (t) => onChanged(v.copyWith(sku: t)),
    );
    final barcode = _BarcodeField(
      value: v.barcode,
      readOnly: ro,
      error: err('barcode'),
      onChanged: (t) => onChanged(v.copyWith(barcode: t)),
    );
    final usd = KTextField(
      label: l10n.catalogPriceUsd,
      prefixText: r'$ ',
      initialValue: centsInput(price),
      readOnly: ro,
      errorText: err('price_cents'),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      onChanged: (t) =>
          onChanged(v.copyWith(priceCents: () => parseUsdCents(t))),
    );
    final khr = _ReadOnlyValue(
      label: l10n.catalogPriceKhr,
      value: price == null ? '—' : formatKhrAmount(usdCentsToKhr(price, rate)),
    );
    final stock = v.isNew
        ? KTextField(
            label: l10n.catalogOpeningStock,
            initialValue: v.initialQty?.toString() ?? '',
            readOnly: ro,
            errorText: err('initial_qty'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (t) =>
                onChanged(v.copyWith(initialQty: () => int.tryParse(t))),
          )
        : Row(
            children: [
              Expanded(
                child: _ReadOnlyValue(
                  label: l10n.catalogOnHand,
                  value: '${v.onHand}',
                ),
              ),
              Expanded(
                child: _ReadOnlyValue(
                  label: l10n.catalogReserved,
                  value: '${v.reserved}',
                ),
              ),
            ],
          );
    final (pill, tone) = variantStockPill(l10n, v);
    final title = Row(
      children: [
        Expanded(
          child: Text(
            v.attributes.isEmpty
                ? '${l10n.catalogVariant} ${index + 1}'
                : v.attributes.values.join(' / '),
            style: k.text.label.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (!v.isNew && v.stocked) KStatusPill(label: pill, tone: tone),
        const SizedBox(width: 8),
        Text(l10n.catalogSell, style: k.text.small),
        Switch(
          value: v.active,
          onChanged: ro ? null : (on) => onChanged(v.copyWith(active: on)),
        ),
        if (onRemove != null && !ro)
          KIconButton(
            icon: KIcons.delete,
            label: l10n.catalogRemoveVariant,
            onPressed: onRemove,
          ),
      ],
    );

    return Semantics(
      container: true,
      label: v.label(),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: v.active ? k.colors.surface : k.colors.soft,
          border: Border.all(color: k.colors.line),
          borderRadius: BorderRadius.circular(KRadius.input),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: 8),
            if (wide) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: sku),
                  const SizedBox(width: 12),
                  Expanded(child: barcode),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: usd),
                  const SizedBox(width: 12),
                  Expanded(child: khr),
                  const SizedBox(width: 12),
                  Expanded(child: stock),
                ],
              ),
            ] else ...[
              sku,
              const SizedBox(height: 12),
              barcode,
              const SizedBox(height: 12),
              usd,
              const SizedBox(height: 8),
              khr,
              const SizedBox(height: 12),
              stock,
            ],
          ],
        ),
      ),
    );
  }
}

/// Barcode input with a camera scan button where a camera is supported.
class _BarcodeField extends StatefulWidget {
  const _BarcodeField({
    required this.value,
    required this.readOnly,
    required this.error,
    required this.onChanged,
  });

  final String value;
  final bool readOnly;
  final String? error;
  final ValueChanged<String> onChanged;

  @override
  State<_BarcodeField> createState() => _BarcodeFieldState();
}

class _BarcodeFieldState extends State<_BarcodeField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    _controller.text = code;
    widget.onChanged(code);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KTextField(
      label: l10n.catalogBarcode,
      optional: true,
      controller: _controller,
      readOnly: widget.readOnly,
      errorText: widget.error,
      onChanged: widget.onChanged,
      suffix: widget.readOnly || !cameraScanSupported(defaultTargetPlatform)
          ? null
          : KIconButton(
              icon: KIcons.camera,
              label: l10n.catalogScanBarcode,
              onPressed: _scan,
            ),
    );
  }
}

class _ReadOnlyValue extends StatelessWidget {
  const _ReadOnlyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: k.text.label.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: k.text.body.copyWith(color: k.colors.ink2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuotesCard extends StatelessWidget {
  const _QuotesCard({
    required this.draft,
    required this.readOnly,
    required this.issues,
    required this.onChanged,
  });

  final ProductDraft draft;
  final bool readOnly;
  final List<FieldIssue> issues;
  final ValueChanged<ProductDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ro = readOnly;
    return EditorCard(
      title: l10n.catalogQuotes,
      trailing: draft.rfqEnabled
          ? KStatusPill(label: l10n.catalogQuoteEnabled, tone: KTone.violet)
          : null,
      children: [
        SwitchTile(
          title: l10n.catalogQuoteSwitch,
          subtitle: l10n.catalogQuoteSwitchSub,
          value: draft.rfqEnabled,
          onChanged: ro
              ? null
              : (on) => onChanged(draft.copyWith(rfqEnabled: on)),
        ),
        if (draft.rfqEnabled)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: KTextField(
                  label: l10n.catalogMinQuoteQty,
                  initialValue: draft.rfqMinQty?.toString() ?? '',
                  readOnly: ro,
                  suffix: Text(l10n.catalogPieces),
                  errorText: issueFor(l10n, issues, 'rfq_min_qty'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (t) => onChanged(
                    draft.copyWith(rfqMinQty: () => int.tryParse(t)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: KTextField(
                  label: l10n.catalogMultiples,
                  initialValue: '${draft.rfqMultiple}',
                  readOnly: ro,
                  suffix: Text(l10n.catalogPieces),
                  errorText: issueFor(l10n, issues, 'rfq_multiple'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (t) => onChanged(
                    draft.copyWith(rfqMultiple: int.tryParse(t) ?? 0),
                  ),
                ),
              ),
            ],
          ),
        KBanner(message: l10n.catalogQuoteInfo, icon: KIcons.info),
      ],
    );
  }
}

class _StockOverview extends StatelessWidget {
  const _StockOverview({required this.draft});

  final ProductDraft draft;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final saved = [
      for (final v in draft.variants)
        if (!v.isNew) v,
    ];
    final most = saved.fold(1, (m, v) => v.onHand > m ? v.onHand : m);
    return EditorCard(
      title: l10n.catalogStockOverview,
      trailing: KButton.ghost(
        label: l10n.adminSectionInventory,
        size: KButtonSize.sm,
        onPressed: () => context.go(AppRoutes.adminInventory),
      ),
      children: [
        for (final v in saved)
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(v.label(), style: k.text.small)),
                    Text(
                      v.available <= 0
                          ? l10n.catalogSoldOutQty(v.available)
                          : v.lowStockAt > 0
                          ? l10n.catalogStockAlertAt(v.available, v.lowStockAt)
                          : '${v.available}',
                      style: k.text.small.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                KProgressBar(
                  value: (v.onHand / most).clamp(0, 1).toDouble(),
                  ok: v.available > v.lowStockAt,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PriceHistory extends ConsumerWidget {
  const _PriceHistory({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final history = ref.watch(priceHistoryProvider(productId));
    return EditorCard(
      title: l10n.catalogPriceHistory,
      children: [
        switch (history) {
          AsyncValue(:final value?) when value.isEmpty => Text(
            l10n.catalogPriceHistoryEmpty,
            style: k.text.small.copyWith(color: k.colors.muted),
          ),
          AsyncValue(:final value?) => KTimeline(
            steps: [
              for (final change in value)
                KTimelineStep(
                  title: change.isNew
                      ? l10n.catalogPriceLaunched(
                          change.sku,
                          formatUsd(change.newCents ?? 0),
                        )
                      : l10n.catalogPriceChanged(
                          change.sku,
                          formatUsd(change.oldCents ?? 0),
                          formatUsd(change.newCents ?? 0),
                        ),
                  subtitle: l10n.catalogByOn(
                    '${formatDayMonth(l10n, change.at)}, ${formatTime(l10n, change.at)}',
                    change.actorName ?? l10n.catalogUnknownStaff,
                  ),
                  state: KStepState.done,
                ),
            ],
          ),
          AsyncValue(hasError: true) => Text(
            l10n.catalogErrUnknown,
            style: k.text.small.copyWith(color: k.colors.muted),
          ),
          _ => const KSkeleton(height: 60),
        },
      ],
    );
  }
}
