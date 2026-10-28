import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/time/date_format.dart';
import '../../../../core/ui/k_ui.dart';
import '../../../catalog/domain/product_draft.dart' show Spec;
import '../../domain/product_detail.dart';
import '../../domain/reviews.dart';
import 'product_detail_providers.dart';

/// C-05 Description: the text, collapsed to a few lines with "Read more",
/// and the highlights as ticked bullets.
class PdDescriptionPanel extends StatefulWidget {
  const PdDescriptionPanel({super.key, required this.product});

  final ProductDetail product;

  @override
  State<PdDescriptionPanel> createState() => _PdDescriptionPanelState();
}

class _PdDescriptionPanelState extends State<PdDescriptionPanel> {
  static const _collapsedLines = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final text = widget.product.description.of(lang).trim();
    final highlights = widget.product.highlights;
    if (text.isEmpty && highlights.isEmpty) {
      return Text(
        l10n.pdDescriptionEmpty,
        style: k.text.body.copyWith(color: k.colors.muted),
      );
    }
    final style = k.text.body.copyWith(color: k.colors.ink2);
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: _collapsedLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: box.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (text.isNotEmpty)
              Text(
                text,
                style: style,
                maxLines: _expanded ? null : _collapsedLines,
                overflow: _expanded ? null : TextOverflow.ellipsis,
              ),
            for (final h in highlights) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KIcon(KIcons.check, size: 18, color: k.colors.ok),
                  const SizedBox(width: 10),
                  Expanded(child: Text(h.of(lang), style: style)),
                ],
              ),
            ],
            if (overflows) ...[
              const SizedBox(height: 4),
              KButton.ghost(
                label: _expanded ? l10n.pdReadLess : l10n.pdReadMore,
                size: KButtonSize.sm,
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// C-05a Specifications: brand and colours first, then the product's own
/// rows, in a card.
class PdSpecsPanel extends StatelessWidget {
  const PdSpecsPanel({super.key, required this.product});

  final ProductDetail product;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final colours = product.valuesOf('colour');
    final rows = [
      if (product.brand != null && product.brand!.trim().isNotEmpty)
        Spec(name: l10n.pdSpecBrand, value: product.brand!),
      ...product.specs.take(1),
      if (colours.isNotEmpty)
        Spec(name: l10n.pdAxisColour, value: colours.join(', ')),
      ...product.specs.skip(1),
    ];
    if (product.specs.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rows.isNotEmpty) ...[
            _table(context, rows),
            const SizedBox(height: 12),
          ],
          Text(l10n.pdSpecsEmpty, style: k.text.body.copyWith(color: c.muted)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _table(context, rows),
        const SizedBox(height: 12),
        Text(l10n.pdSpecsNote, style: k.text.caption.copyWith(color: c.muted)),
      ],
    );
  }

  Widget _table(BuildContext context, List<Spec> rows) {
    final k = context.k;
    final c = k.colors;
    return Container(
      key: const Key('pd-specs'),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(KRadius.card),
      ),
      child: Column(
        children: [
          for (final (i, s) in rows.indexed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: i == 0 ? null : Border(top: BorderSide(color: c.line)),
              ),
              child: MergeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 128,
                      child: Text(
                        s.name,
                        style: k.text.small.copyWith(color: c.muted),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        s.value,
                        style: k.text.small.copyWith(
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// C-05b Reviews: summary with bars, filter chips and the latest reviews.
/// Until F32 brings the data, an empty state.
class PdReviewsPanel extends ConsumerStatefulWidget {
  const PdReviewsPanel({super.key, required this.product});

  final ProductDetail product;

  @override
  ConsumerState<PdReviewsPanel> createState() => _PdReviewsPanelState();
}

enum _ReviewFilter { all, photos, five, four, threeAndBelow }

class _PdReviewsPanelState extends ConsumerState<PdReviewsPanel> {
  _ReviewFilter _filter = _ReviewFilter.all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reviews = ref.watch(productReviewsProvider(widget.product.id));
    return switch (reviews) {
      AsyncData(:final value) when !value.isEmpty => _list(context, value),
      AsyncLoading() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: KSpinner(blue: true)),
      ),
      _ => KEmptyState(
        key: const Key('pd-reviews-empty'),
        icon: KIcons.star,
        title: l10n.pdReviewsEmptyTitle,
        message: l10n.pdReviewsEmptyBody,
        compact: true,
      ),
    };
  }

  Widget _list(BuildContext context, ProductReviews r) {
    final l10n = AppLocalizations.of(context);
    final shown = [
      for (final item in r.items)
        if (switch (_filter) {
          _ReviewFilter.all => true,
          _ReviewFilter.photos => item.photoUrls.isNotEmpty,
          _ReviewFilter.five => item.rating == 5,
          _ReviewFilter.four => item.rating == 4,
          _ReviewFilter.threeAndBelow => item.rating <= 3,
        })
          item,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PdReviewSummary(reviews: r),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (f, label) in [
                (_ReviewFilter.all, l10n.pdReviewFilterAll),
                (_ReviewFilter.photos, l10n.pdReviewFilterPhotos(r.withPhotos)),
                (_ReviewFilter.five, '5'),
                (_ReviewFilter.four, '4'),
                (_ReviewFilter.threeAndBelow, l10n.pdReviewFilter3Below),
              ]) ...[
                KChip(
                  label: label,
                  selected: _filter == f,
                  onTap: () => setState(() => _filter = f),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        for (final item in shown) ...[
          const SizedBox(height: 12),
          PdReviewCard(review: item),
        ],
        if (r.total > r.items.length) ...[
          const SizedBox(height: 16),
          KButton.outline(
            label: l10n.pdSeeAllReviews(r.total),
            expand: true,
            // The full list (and writing a review) is F32.
            onPressed: null,
          ),
        ],
      ],
    );
  }
}

/// "4.6", stars, "128 reviews", and a bar per star rating.
class PdReviewSummary extends StatelessWidget {
  const PdReviewSummary({super.key, required this.reviews});

  final ProductReviews reviews;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final avg = reviews.average.toStringAsFixed(1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                avg,
                style: k.text.display.copyWith(fontSize: 40, height: 44 / 40),
              ),
              KStars(rating: reviews.average, size: 14),
              const SizedBox(height: 4),
              Text(
                l10n.pdReviewCount(reviews.total),
                style: k.text.caption.copyWith(color: c.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: [
              for (var stars = 5; stars >= 1; stars--)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: MergeSemantics(
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          child: Text('$stars', style: k.text.caption),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: reviews.shareOf(stars),
                              minHeight: 6,
                              backgroundColor: c.line,
                              color: c.star,
                              semanticsLabel: l10n.pdStarsA11y('$stars'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${reviews.byStars[stars] ?? 0}',
                            textAlign: TextAlign.end,
                            style: k.text.caption.copyWith(color: c.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class PdReviewCard extends StatelessWidget {
  const PdReviewCard({super.key, required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final body = k.text.small.copyWith(fontSize: 14, color: c.ink2);
    return KCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              KAvatar(review.initials, size: KAvatarSize.sm),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.author,
                      style: k.text.small.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      formatShortDate(l10n, review.createdAt),
                      style: k.text.caption.copyWith(color: c.muted),
                    ),
                  ],
                ),
              ),
              KStars(rating: review.rating.toDouble(), size: 14),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            review.variantLabel == null
                ? l10n.pdReviewVerifiedOnly
                : l10n.pdReviewVerified(review.variantLabel!),
            style: k.text.caption.copyWith(color: c.muted),
          ),
          if (review.body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.body, style: body),
          ],
          if (review.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                for (final (i, url) in review.photoUrls.indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(KRadius.tag),
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: KNetworkImage(
                        url: url,
                        semanticLabel: l10n.pdReviewPhotoA11y(
                          i + 1,
                          review.photoUrls.length,
                        ),
                        fallback: ColoredBox(color: c.soft),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (review.reply != null) ...[
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.only(left: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.tint,
                borderRadius: BorderRadius.circular(KRadius.input),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.pdReplyFromK,
                    style: k.text.caption.copyWith(
                      fontWeight: FontWeight.w800,
                      color: c.primaryInk,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(review.reply!, style: body),
                ],
              ),
            ),
          ],
          if (review.helpful > 0) ...[
            const SizedBox(height: 4),
            KButton.ghost(
              label: l10n.pdHelpful(review.helpful),
              size: KButtonSize.sm,
              // Voting is F32.
              onPressed: null,
            ),
          ],
        ],
      ),
    );
  }
}

/// The three tabs and their panels in one place, for the page.
enum PdTab { description, specs, reviews }

Widget pdTabPanel(PdTab tab, ProductDetail product) => switch (tab) {
  PdTab.description => PdDescriptionPanel(product: product),
  PdTab.specs => PdSpecsPanel(product: product),
  PdTab.reviews => PdReviewsPanel(product: product),
};
