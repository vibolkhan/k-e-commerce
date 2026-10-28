import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/khr_rate_provider.dart';
import '../../../core/money/money_format.dart';
import '../../../core/ui/k_ui.dart';
import '../domain/product_view.dart';
import 'catalog_providers.dart';

/// A-05a Preview: the saved product as customers read it (through the same
/// repository the store uses), as a shopper's card and a business buyer's.
Future<void> showProductPreview(
  BuildContext context, {
  required String productId,
  required bool active,
  required bool unsavedChanges,
}) => showKBottomSheet<void>(
  context,
  title: AppLocalizations.of(context).catalogPreviewTitle,
  builder: (_) => ProductPreview(
    productId: productId,
    active: active,
    unsavedChanges: unsavedChanges,
  ),
);

class ProductPreview extends ConsumerWidget {
  const ProductPreview({
    super.key,
    required this.productId,
    required this.active,
    required this.unsavedChanges,
  });

  final String productId;
  final bool active;
  final bool unsavedChanges;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final rate = ref.watch(khrRateValueProvider);
    final product = ref.watch(productViewProvider(productId));

    Widget image(ProductView p) => KProductArt(
      icon: KIcons.package,
      image: p.mainImageUrl == null
          ? null
          : Image.network(
              p.mainImageUrl!,
              fit: BoxFit.cover,
              semanticLabel: p.imageAlts.first.of(lang),
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: switch (product) {
        AsyncValue(:final value?) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!active) ...[
              KBanner(message: l10n.catalogPreviewDraftNote, icon: KIcons.info),
              const SizedBox(height: 12),
            ],
            if (unsavedChanges) ...[
              KBanner(
                message: l10n.catalogPreviewUnsavedChanges,
                tone: KBannerTone.warn,
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _Labelled(
                  label: l10n.catalogPreviewRetail,
                  child: KProductCard(
                    name: value.name.of(lang),
                    image: image(value),
                    price: formatUsd(value.fromPriceCents ?? 0),
                    khrAmount: formatKhrAmount(
                      usdCentsToKhr(value.fromPriceCents ?? 0, rate),
                    ),
                    rating: value.ratingCount > 0 ? value.ratingAvg : null,
                    ratingCount: value.ratingCount > 0
                        ? value.ratingCount
                        : null,
                    soldOut: value.soldOut,
                  ),
                ),
                if (value.rfqEnabled)
                  _Labelled(
                    label: l10n.catalogPreviewBusiness,
                    child: KProductCard.business(
                      name: value.name.of(lang),
                      image: image(value),
                      minQuantity: value.rfqMinQty == null
                          ? null
                          : l10n.catalogMinPieces(value.rfqMinQty!),
                      soldOut: value.soldOut,
                    ),
                  ),
              ],
            ),
          ],
        ),
        AsyncValue(hasValue: true) => KEmptyState(
          icon: KIcons.package,
          title: l10n.catalogNotFound,
          compact: true,
        ),
        AsyncValue(hasError: true) => KEmptyState(
          icon: KIcons.error,
          title: l10n.catalogErrUnknown,
          compact: true,
        ),
        _ => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: KSpinner()),
        ),
      },
    );
  }
}

class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: k.text.overline.copyWith(color: k.colors.muted)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
