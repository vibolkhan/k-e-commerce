import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/money/khr_rate_provider.dart';
import '../../../../core/money/money_format.dart';
import '../../../../core/ui/k_ui.dart';
import '../../../cart/domain/cart.dart';
import '../../../cart/presentation/cart_providers.dart';
import '../../domain/product_detail.dart';
import '../store_widgets.dart';
import 'pd_widgets.dart';

/// What the sheet added, for the "Added to cart" toast (C-05d).
typedef PdAdded = ({DetailVariant variant, int qty});

/// C-05c: pick the variant and quantity, then add to the cart. Choices made
/// here are passed back through [onSelection] so the page follows them.
Future<PdAdded?> showChooseOptions(
  BuildContext context, {
  required VariantSelection selection,
  required ValueChanged<VariantSelection> onSelection,
}) => showKBottomSheet<PdAdded>(
  context,
  showClose: false,
  builder: (_) =>
      ChooseOptionsSheet(selection: selection, onSelection: onSelection),
);

class ChooseOptionsSheet extends ConsumerStatefulWidget {
  const ChooseOptionsSheet({
    super.key,
    required this.selection,
    required this.onSelection,
  });

  final VariantSelection selection;
  final ValueChanged<VariantSelection> onSelection;

  @override
  ConsumerState<ChooseOptionsSheet> createState() => _ChooseOptionsSheetState();
}

class _ChooseOptionsSheetState extends ConsumerState<ChooseOptionsSheet> {
  late VariantSelection _selection = widget.selection;
  int _qty = 1;
  bool _adding = false;

  ProductDetail get _product => _selection.product;

  void _select(VariantSelection next) {
    setState(() => _selection = next);
    widget.onSelection(next);
  }

  Future<void> _add(DetailVariant variant, int lineMax) async {
    setState(() => _adding = true);
    await ref
        .read(cartProvider.notifier)
        .add(
          productId: _product.id,
          variantId: variant.id,
          qty: _qty,
          max: lineMax,
        );
    if (!mounted) return;
    Navigator.of(context).pop<PdAdded>((variant: variant, qty: _qty));
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final variant = _selection.variant;
    final lineMax = _selection.maxQty;
    final inCart = variant == null
        ? 0
        : qtyInCart(ref.watch(cartProvider), variant.id);
    // What can still go in: the line's limit less what's already there.
    final canAdd = (lineMax - inCart).clamp(0, lineMax);
    final qty = _qty.clamp(1, canAdd < 1 ? 1 : canAdd);
    if (qty != _qty) _qty = qty;
    final price = variant?.priceCents;
    final image = _product.images.isEmpty
        ? null
        : _product
              .images[variant == null
                  ? 0
                  : _product.imageIndexFor(variant) ?? 0]
              .url;

    return SingleChildScrollView(
      key: const Key('pd-options-sheet'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(KRadius.box),
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: KNetworkImage(
                    url: image,
                    fallback: productArtFor(_product.id, _product.name.en),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        _product.name.of(lang),
                        style: k.text.h3,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (price != null) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          Text(
                            formatUsd(price),
                            style: k.text.price.copyWith(
                              fontSize: 20,
                              height: 26 / 20,
                            ),
                          ),
                          Text(
                            formatKhr(
                              l10n,
                              price,
                              rate: ref.watch(khrRateValueProvider),
                            ),
                            style: k.text.small.copyWith(color: c.muted),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    if (variant != null && variant.inStock)
                      KStatusPill(
                        label: l10n.pdInStockCount(variant.available),
                        tone: KTone.green,
                        dot: true,
                      )
                    else
                      KStatusPill(
                        label: l10n.pdOutOfStock,
                        tone: KTone.red,
                        dot: true,
                      ),
                  ],
                ),
              ),
              KIconButton(
                icon: KIcons.close,
                label: l10n.uiClose,
                style: KIconButtonStyle.soft,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(height: 1, color: c.line),
          if (_product.axes.isNotEmpty) ...[
            const SizedBox(height: 16),
            PdOptionPicker(
              selection: _selection,
              onChanged: _select,
              swatches: false,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.pdQuantity, style: k.text.label),
                    if (_product.maxPerOrder != null)
                      Text(
                        l10n.pdMaxPerOrder(_product.maxPerOrder!),
                        style: k.text.caption.copyWith(color: c.muted),
                      ),
                    if (inCart > 0)
                      Text(
                        canAdd > 0
                            ? l10n.pdInCartAlready(inCart)
                            : l10n.pdLimitReached,
                        style: k.text.caption.copyWith(color: c.muted),
                      ),
                  ],
                ),
              ),
              KQtyStepper(
                key: const Key('pd-qty'),
                value: qty,
                max: canAdd < 1 ? 1 : canAdd,
                onChanged: canAdd < 1 ? null : (v) => setState(() => _qty = v),
              ),
            ],
          ),
          if (_product.sameDay) ...[
            const SizedBox(height: 16),
            const PdCutoffBanner(),
          ],
          const SizedBox(height: 16),
          KButton(
            key: const Key('pd-sheet-add'),
            label: price == null
                ? l10n.pdAddToCart
                : l10n.pdAddToCartPrice(formatUsd(price * qty)),
            icon: KIcons.cart,
            size: KButtonSize.lg,
            expand: true,
            loading: _adding,
            onPressed: variant == null || canAdd < 1 || _adding
                ? null
                : () => _add(variant, lineMax),
          ),
        ],
      ),
    );
  }
}
