import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/khr_rate_provider.dart';
import '../../../core/money/money_format.dart';
import '../../../core/router/app_role.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/ui/k_ui.dart';
import '../domain/browse.dart';
import '../domain/search.dart';
import '../domain/storefront.dart';
import 'store_widgets.dart';

/// [text] with the runs matching [query] in [matchWeight] and the rest in
/// [restWeight]: product names bold what was typed, suggested words bold
/// the completion (C-04).
TextSpan matchSpan(
  String text,
  String query, {
  required TextStyle style,
  required FontWeight matchWeight,
  required FontWeight restWeight,
}) => TextSpan(
  style: style,
  children: [
    for (final run in matchRuns(text, query))
      TextSpan(
        text: run.text,
        style: TextStyle(fontWeight: run.match ? matchWeight : restWeight),
      ),
  ],
);

/// One row of the C-04 suggestions: an icon or thumbnail, a title, an
/// optional subtitle and a chevron. At least 52 px tall.
class SuggestionRow extends StatelessWidget {
  const SuggestionRow({
    super.key,
    required this.title,
    required this.semanticLabel,
    required this.onTap,
    this.icon,
    this.thumbnail,
    this.subtitle,
  });

  final InlineSpan title;
  final String semanticLabel;
  final VoidCallback onTap;
  final KIconData? icon;
  final Widget? thumbnail;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: thumbnail == null ? 52 : 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                if (thumbnail != null)
                  SizedBox.square(dimension: 44, child: thumbnail)
                else
                  KIcon(icon ?? KIcons.search, size: 20, color: c.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text.rich(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: k.text.caption.copyWith(color: c.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                KIcon(KIcons.chevronRight, size: 18, color: c.ink3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A product in the C-04 suggestions: "Wireless **Head**phones Pro",
/// "$49.00 · Audio" (the category alone for business buyers).
class SuggestedProductRow extends ConsumerWidget {
  const SuggestedProductRow({
    super.key,
    required this.product,
    required this.query,
    required this.onTap,
  });

  final SuggestedProduct product;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = context.k;
    final lang = Localizations.localeOf(context).languageCode;
    final name = product.name.of(lang);
    final price = product.priceCents;
    final subtitle = [
      if (price != null) formatUsd(price),
      if (product.category != null) product.category!.of(lang),
    ].join(' · ');
    return SuggestionRow(
      title: matchSpan(
        name,
        query,
        style: k.text.body.copyWith(fontSize: 14, color: k.colors.ink),
        matchWeight: FontWeight.w800,
        restWeight: FontWeight.w600,
      ),
      subtitle: subtitle.isEmpty ? null : subtitle,
      semanticLabel: [name, if (subtitle.isNotEmpty) subtitle].join(', '),
      thumbnail: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: KNetworkImage(
          url: product.imageUrl,
          fallback: productArt(
            BrowseItem(id: product.id, slug: '', name: product.name),
          ),
        ),
      ),
      onTap: onTap,
    );
  }
}

/// A C-04a result as a list row (phones): photo, name, rating, and the
/// price with ≈ KHR, or "Price on quote" for business buyers.
class SearchResultRow extends ConsumerWidget {
  const SearchResultRow({super.key, required this.item, required this.role});

  final BrowseItem item;
  final AppRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final name = item.name.of(lang);
    final price = role == AppRole.business ? null : item.priceCents;
    final rate = ref.watch(khrRateValueProvider);
    final khr = price == null
        ? null
        : formatKhrAmount(usdCentsToKhr(price, rate));
    final caption = k.text.caption.copyWith(color: c.muted);
    final semantics = [
      name,
      if (item.ratingCount > 0)
        l10n.uiRatedOutOf5(item.ratingAvg.toStringAsFixed(1)),
      if (price != null) ...[
        formatUsd(price),
        l10n.uiKhrApprox(khr!),
      ] else
        l10n.uiPriceOnQuote,
      if (item.soldOut) l10n.uiSoldOut,
    ].join(', ');
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => context.push(AppRoutes.product(role.homePath, item.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 64,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(KRadius.input),
                  child: KNetworkImage(
                    url: item.imageUrl,
                    fallback: productArt(item),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: k.text.body.copyWith(
                        fontSize: 14,
                        height: 19 / 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (item.ratingCount > 0) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          KIcon(
                            KIcons.star,
                            size: 14,
                            color: c.star,
                            fill: c.star,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            item.ratingAvg.toStringAsFixed(1),
                            style: k.text.caption.copyWith(
                              fontWeight: FontWeight.w700,
                              color: c.ink2,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text('(${item.ratingCount})', style: caption),
                        ],
                      ),
                    ],
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (price != null) ...[
                          Text(
                            formatUsd(price),
                            style: k.text.body.copyWith(
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          Text(l10n.uiKhrApprox(khr!), style: caption),
                        ] else ...[
                          Text(
                            l10n.uiPriceOnQuote,
                            style: k.text.small.copyWith(
                              fontWeight: FontWeight.w700,
                              color: c.primaryInk,
                            ),
                          ),
                          if (item.rfqMinQty != null)
                            Text(
                              l10n.uiMinQuantity('${item.rfqMinQty}'),
                              style: caption,
                            ),
                        ],
                        if (item.soldOut)
                          KStatusPill(label: l10n.uiSoldOut, tone: KTone.ink),
                      ],
                    ),
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

/// Skeleton list rows while results load on a phone.
class SearchRowSkeleton extends StatelessWidget {
  const SearchRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        KSkeleton(width: 64, height: 64, radius: KRadius.input),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KSkeleton(height: 14),
              SizedBox(height: 8),
              KSkeleton(width: 60, height: 12),
              SizedBox(height: 8),
              KSkeleton(width: 90, height: 16),
            ],
          ),
        ),
      ],
    ),
  );
}

/// A section title for C-04 with an optional trailing action ("Clear").
class SearchSectionHead extends StatelessWidget {
  const SearchSectionHead({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kMinTap),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: k.text.h3.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Category chips (C-04 "Popular categories", C-04b). Opens the category's
/// product list.
class CategoryChips extends StatelessWidget {
  const CategoryChips({
    super.key,
    required this.categories,
    required this.shell,
  });

  final List<StoreCategory> categories;
  final String shell;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return Wrap(
      spacing: 8,
      children: [
        for (final c in categories)
          KChip(
            key: Key('popular-${c.slug}'),
            label: c.name.of(lang),
            icon: categoryIcon(c.icon),
            onTap: () => context.go(AppRoutes.category(shell, c.slug)),
          ),
      ],
    );
  }
}

/// "Did you mean **headphones**?" with the suggestion as a link (C-04b).
class DidYouMean extends StatelessWidget {
  const DidYouMean({super.key, required this.suggestion, required this.onTap});

  final String suggestion;
  final VoidCallback onTap;

  /// Stands in for the suggestion so the sentence around it can be split
  /// in any language.
  static const _marker = '\u{E000}';

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final parts = l10n.storeDidYouMean(_marker).split(_marker);
    final style = k.text.body.copyWith(color: k.colors.ink2);
    return Semantics(
      button: true,
      label: l10n.storeDidYouMean(suggestion),
      excludeSemantics: true,
      onTap: onTap,
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (parts.first.isNotEmpty) Text(parts.first, style: style),
          InkWell(
            key: const Key('did-you-mean'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(KRadius.tag),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTap),
              child: Center(
                widthFactor: 1,
                child: Text(
                  suggestion,
                  style: style.copyWith(
                    color: k.colors.primary,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                    decorationColor: k.colors.primary,
                  ),
                ),
              ),
            ),
          ),
          if (parts.length > 1 && parts.last.isNotEmpty)
            Text(parts.last, style: style),
        ],
      ),
    );
  }
}

/// The "Try this" card on C-04b.
class SearchTipsCard extends StatelessWidget {
  const SearchTipsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    Widget tip(KIconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          KIcon(icon, size: 18, color: c.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: k.text.small.copyWith(color: c.ink2)),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(KRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.storeTryThis,
              style: k.text.label.copyWith(fontSize: 14, color: c.ink),
            ),
          ),
          const SizedBox(height: 2),
          tip(KIcons.edit, l10n.storeTipSpelling),
          tip(KIcons.search, l10n.storeTipFewerWords),
          tip(KIcons.categories, l10n.storeTipBrowse),
        ],
      ),
    );
  }
}
