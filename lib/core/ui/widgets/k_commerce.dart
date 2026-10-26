import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../icons/k_icon.dart';
import '../icons/k_icons.dart';
import '../theme/k_theme.dart';
import '../theme/k_tokens.dart';
import 'k_status_pill.dart';

/// − value + stepper, 44 px. Buttons disable at [min] / [max]. The server
/// still validates stock; this only bounds the input.
class KQtyStepper extends StatelessWidget {
  const KQtyStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max,
  });

  final int value;
  final int min;
  final int? max;

  /// Null disables both buttons.
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final canDec = onChanged != null && value > min;
    final canInc = onChanged != null && (max == null || value < max!);

    Widget btn(KIconData icon, String label, bool enabled, int delta) =>
        Semantics(
          button: true,
          enabled: enabled,
          label: label,
          excludeSemantics: true,
          onTap: enabled ? () => onChanged!(value + delta) : null,
          child: InkWell(
            onTap: enabled ? () => onChanged!(value + delta) : null,
            borderRadius: BorderRadius.circular(KRadius.input),
            child: SizedBox(
              width: 44,
              height: 42,
              child: Center(
                child: KIcon(icon, size: 18, color: enabled ? c.ink : c.line2),
              ),
            ),
          ),
        );

    return Semantics(
      label: l10n.uiQuantity,
      value: '$value',
      container: true,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line2),
          borderRadius: BorderRadius.circular(KRadius.input),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              btn(KIcons.minus, l10n.uiDecrease, canDec, -1),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 28),
                child: ExcludeSemantics(
                  child: Text(
                    '$value',
                    textAlign: TextAlign.center,
                    style: k.text.body.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              btn(KIcons.plus, l10n.uiIncrease, canInc, 1),
            ],
          ),
        ),
      ),
    );
  }
}

/// Five stars, filled to the nearest whole star.
class KStars extends StatelessWidget {
  const KStars({super.key, required this.rating, this.size = 20});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.k.colors;
    final l10n = AppLocalizations.of(context);
    final filled = rating.round();
    return Semantics(
      label: l10n.uiRatedOutOf5(rating.toStringAsFixed(1)),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 5; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              KIcon(
                KIcons.star,
                size: size,
                color: i < filled ? c.star : c.line2,
                fill: i < filled ? c.star : c.line2,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 8 px progress bar; [ok] turns it green (e.g. free delivery unlocked).
class KProgressBar extends StatelessWidget {
  const KProgressBar({super.key, required this.value, this.ok = false});

  final double value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final c = context.k.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: 8,
        backgroundColor: c.line,
        color: ok ? c.ok : c.primary,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// Product tile for grids. The retail variant shows price and KHR; the
/// [KProductCard.business] variant has no price parameter at all — business
/// buyers only ever see "Price on quote" and the minimum quantity.
class KProductCard extends StatelessWidget {
  const KProductCard({
    super.key,
    required this.name,
    required this.image,
    required String this.price,
    this.khrAmount,
    this.rating,
    this.ratingCount,
    this.wishlisted,
    this.onWishlist,
    this.soldOut = false,
    this.onTap,
  }) : minQuantity = null;

  const KProductCard.business({
    super.key,
    required this.name,
    required this.image,
    this.minQuantity,
    this.rating,
    this.ratingCount,
    this.soldOut = false,
    this.onTap,
  }) : price = null,
       khrAmount = null,
       wishlisted = null,
       onWishlist = null;

  final String name;

  /// Square art: a [KProductArt] or a product photo.
  final Widget image;

  /// Formatted USD price incl. VAT, e.g. `$49.00`. Null on business cards.
  final String? price;

  /// Formatted riel amount, e.g. `200,900`; shown as "≈ KHR 200,900".
  final String? khrAmount;

  /// Minimum order, already worded, e.g. "20 reams".
  final String? minQuantity;
  final double? rating;
  final int? ratingCount;

  /// Null hides the heart.
  final bool? wishlisted;
  final VoidCallback? onWishlist;
  final bool soldOut;
  final VoidCallback? onTap;

  bool get isBusiness => price == null;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(KRadius.card),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  AspectRatio(aspectRatio: 1, child: image),
                  if (wishlisted != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _Heart(on: wishlisted!, onTap: onWishlist),
                    ),
                  if (soldOut)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: KStatusPill(
                        label: l10n.uiSoldOut,
                        tone: KTone.ink,
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 38,
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: k.text.body.copyWith(
                          fontSize: 14,
                          height: 19 / 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (rating != null) ...[
                      const SizedBox(height: 4),
                      _RatingLine(rating: rating!, count: ratingCount),
                    ],
                    const SizedBox(height: 4),
                    if (isBusiness)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: c.tint,
                          borderRadius: BorderRadius.circular(KRadius.tag),
                        ),
                        child: Text(
                          l10n.uiPriceOnQuote,
                          style: k.text.small.copyWith(
                            fontWeight: FontWeight.w700,
                            color: c.primaryInk,
                          ),
                        ),
                      )
                    else
                      Text(
                        price!,
                        style: k.text.body.copyWith(
                          fontSize: 16,
                          height: 22 / 16,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    if (isBusiness && minQuantity != null ||
                        !isBusiness && khrAmount != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        isBusiness
                            ? l10n.uiMinQuantity(minQuantity!)
                            : l10n.uiKhrApprox(khrAmount!),
                        style: k.text.caption.copyWith(
                          fontWeight: FontWeight.w400,
                          color: c.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatingLine extends StatelessWidget {
  const _RatingLine({required this.rating, this.count});
  final double rating;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final style = k.text.caption.copyWith(
      fontWeight: FontWeight.w700,
      color: c.ink2,
    );
    return Semantics(
      label: AppLocalizations.of(
        context,
      ).uiRatedOutOf5(rating.toStringAsFixed(1)),
      excludeSemantics: true,
      child: Row(
        children: [
          KIcon(KIcons.star, size: 14, color: c.star, fill: c.star),
          const SizedBox(width: 4),
          Text(rating.toStringAsFixed(1), style: style),
          if (count != null) ...[
            const SizedBox(width: 4),
            Text('($count)', style: style.copyWith(color: c.muted)),
          ],
        ],
      ),
    );
  }
}

class _Heart extends StatelessWidget {
  const _Heart({required this.on, this.onTap});
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      toggled: on,
      label: on ? l10n.uiWishlistRemove : l10n.uiWishlistAdd,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: kMinTap,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .95),
                shape: BoxShape.circle,
                boxShadow: k.shadow1,
              ),
              alignment: Alignment.center,
              child: KIcon(
                KIcons.heart,
                size: 18,
                color: on ? KColors.heart : c.ink2,
                fill: on ? KColors.heart : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
