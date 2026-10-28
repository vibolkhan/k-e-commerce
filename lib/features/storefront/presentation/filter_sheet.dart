import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/ui/k_ui.dart';
import '../domain/browse.dart';

/// C-03a Filters: price range, brand, rating, in stock and same-day. The
/// button shows how many products match before applying. Business buyers
/// get no price section. Resolves with the new query, or null if closed.
Future<BrowseQuery?> showFilterSheet(
  BuildContext context, {
  required BrowseQuery query,
  required BrowsePage facets,
  required bool business,
  required String cutoff,
  required Future<int> Function(BrowseQuery) count,
}) {
  return showKBottomSheet<BrowseQuery>(
    context,
    showClose: false,
    builder: (_) => FilterSheet(
      query: query,
      facets: facets,
      business: business,
      cutoff: cutoff,
      count: count,
    ),
  );
}

class FilterSheet extends StatefulWidget {
  const FilterSheet({
    super.key,
    required this.query,
    required this.facets,
    required this.business,
    required this.cutoff,
    required this.count,
  });

  final BrowseQuery query;
  final BrowsePage facets;
  final bool business;

  /// Today's cut-off, worded ("3:00 PM").
  final String cutoff;
  final Future<int> Function(BrowseQuery) count;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late BrowseQuery _draft = widget.query;
  late final _min = TextEditingController(
    text: _dollars(widget.query.minCents),
  );
  late final _max = TextEditingController(
    text: _dollars(widget.query.maxCents),
  );
  Timer? _debounce;
  int? _matches;
  bool _counting = false;

  /// Slider range in whole dollars, from the list's price bounds.
  late final int _lo = ((widget.facets.minPriceCents ?? 0) / 100).floor();
  late final int _hi = (((widget.facets.maxPriceCents ?? 10000) + 99) / 100)
      .ceil()
      .clamp(_lo + 1, 1 << 30);

  @override
  void initState() {
    super.initState();
    // The list behind the sheet is the current query's result.
    _matches = widget.facets.total;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  static String _dollars(int? cents) => cents == null
      ? ''
      : (cents / 100).toStringAsFixed(cents % 100 == 0 ? 0 : 2);

  static int? _cents(String text) {
    final v = double.tryParse(text.trim());
    return v == null || v < 0 ? null : (v * 100).round();
  }

  void _change(BrowseQuery next) {
    setState(() => _draft = next);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _recount);
  }

  Future<void> _recount() async {
    final asked = _draft;
    setState(() => _counting = true);
    try {
      final n = await widget.count(asked);
      if (mounted && asked == _draft) {
        setState(() {
          _matches = n;
          _counting = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _counting = false);
    }
  }

  void _reset() {
    _min.clear();
    _max.clear();
    _change(widget.query.cleared());
  }

  void _setPrice({int? min, int? max}) {
    _change(_draft.copyWith(minCents: () => min, maxCents: () => max));
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final brands = widget.facets.brands;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(l10n.storeFilters, style: k.text.title),
              ),
            ),
            KButton.ghost(
              key: const Key('filters-reset'),
              label: l10n.storeReset,
              size: KButtonSize.sm,
              onPressed: _reset,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.business) ...[
                  _Legend(l10n.storePrice),
                  _priceFields(l10n),
                  _priceSlider(l10n),
                  const Divider(height: 32),
                ],
                if (brands.isNotEmpty) ...[
                  _Legend(l10n.storeBrand),
                  for (final b in brands)
                    _CheckRow(
                      key: Key('brand-${b.brand}'),
                      label: b.brand,
                      count: b.count,
                      checked: _draft.brands.contains(b.brand),
                      onChanged: (on) => _change(
                        _draft.copyWith(
                          brands: on
                              ? {..._draft.brands, b.brand}
                              : ({..._draft.brands}..remove(b.brand)),
                        ),
                      ),
                    ),
                  const Divider(height: 32),
                ],
                _Legend(l10n.storeRating),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final r in const [4.0, 3.0])
                      KChip(
                        key: Key('rating-${r.toInt()}'),
                        label: l10n.storeRatingAndUp('${r.toInt()}'),
                        icon: KIcons.star,
                        selected: _draft.minRating == r,
                        onTap: () => _change(
                          _draft.copyWith(
                            minRating: () => _draft.minRating == r ? null : r,
                          ),
                        ),
                      ),
                  ],
                ),
                const Divider(height: 32),
                KSwitchRow(
                  key: const Key('switch-in-stock'),
                  label: l10n.storeInStockOnly,
                  value: _draft.inStock,
                  onChanged: (v) => _change(_draft.copyWith(inStock: v)),
                ),
                const SizedBox(height: 8),
                MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      KSwitchRow(
                        key: const Key('switch-same-day'),
                        label: l10n.storeSameDayDelivery,
                        value: _draft.sameDay,
                        onChanged: (v) => _change(_draft.copyWith(sameDay: v)),
                      ),
                      Text(
                        l10n.storeSameDayDeliveryHint(widget.cutoff),
                        style: k.text.small.copyWith(color: k.colors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        KButton(
          key: const Key('filters-apply'),
          label: _matches == null
              ? l10n.storeShowResultsPending
              : l10n.storeShowResults(_matches!),
          size: KButtonSize.lg,
          expand: true,
          loading: _counting && _matches == null,
          onPressed: () => Navigator.of(context).pop(_draft),
        ),
      ],
    );
  }

  Widget _priceFields(AppLocalizations l10n) {
    final k = context.k;
    final formatters = [
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
    ];
    return Row(
      children: [
        Expanded(
          child: Semantics(
            label: l10n.storeMinPriceLabel,
            child: KTextField(
              key: const Key('price-min'),
              controller: _min,
              prefixText: l10n.storeMinPrefix,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: formatters,
              onChanged: (v) => _setPrice(min: _cents(v), max: _draft.maxCents),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(l10n.storePriceTo, style: k.text.small),
        ),
        Expanded(
          child: Semantics(
            label: l10n.storeMaxPriceLabel,
            child: KTextField(
              key: const Key('price-max'),
              controller: _max,
              prefixText: l10n.storeMaxPrefix,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: formatters,
              onChanged: (v) => _setPrice(min: _draft.minCents, max: _cents(v)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _priceSlider(AppLocalizations l10n) {
    final lo = _lo.toDouble();
    final hi = _hi.toDouble();
    final start = ((_draft.minCents ?? _lo * 100) / 100).clamp(lo, hi);
    final end = ((_draft.maxCents ?? _hi * 100) / 100).clamp(start, hi);
    return RangeSlider(
      min: lo,
      max: hi,
      values: RangeValues(start, end),
      semanticFormatterCallback: (v) => '\$${v.round()}',
      labels: RangeLabels('\$${start.round()}', '\$${end.round()}'),
      onChanged: (v) {
        final min = v.start.round() <= _lo ? null : v.start.round() * 100;
        final max = v.end.round() >= _hi ? null : v.end.round() * 100;
        _min.text = _dollars(min);
        _max.text = _dollars(max);
        _setPrice(min: min, max: max);
      },
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Semantics(
      header: true,
      child: Text(text, style: context.k.text.label),
    ),
  );
}

/// Checkbox row, 48 px, with a count on the right.
class _CheckRow extends StatelessWidget {
  const _CheckRow({
    super.key,
    required this.label,
    required this.count,
    required this.checked,
    required this.onChanged,
  });

  final String label;
  final int count;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!checked),
        borderRadius: BorderRadius.circular(KRadius.input),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Checkbox(value: checked, onChanged: (v) => onChanged(v ?? false)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: k.text.body.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '$count',
                style: k.text.small.copyWith(color: k.colors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
