import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/khr_rate_provider.dart';
import '../../../core/money/money_format.dart';
import '../../../core/router/app_role.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/time/cutoff.dart';
import '../../../core/time/date_format.dart';
import '../../../core/time/phnom_penh_time.dart';
import '../../../core/ui/k_ui.dart';
import '../../admin/presentation/admin_labels.dart' show durationLabel;
import '../domain/browse.dart';
import '../domain/storefront.dart';
import 'storefront_providers.dart';

/// Placeholder art for a product without photos, picked from its name so
/// the same product always looks the same.
Widget productArt(BrowseItem item, {double radius = 0}) =>
    productArtFor(item.id, item.name.en, radius: radius);

/// [productArt] for a product known by [id] and English [nameEn].
Widget productArtFor(String id, String nameEn, {double radius = 0}) {
  final name = nameEn.toLowerCase();
  const byWord = <String, KIconData>{
    'headphone': KIcons.headphones,
    'headset': KIcons.headphones,
    'earbud': KIcons.headphones,
    'watch': KIcons.watch,
    'sneaker': KIcons.sneaker,
    'shoe': KIcons.sneaker,
    'backpack': KIcons.backpack,
    'bag': KIcons.backpack,
    'mug': KIcons.mug,
    'lamp': KIcons.lamp,
    'bottle': KIcons.bottle,
    'shirt': KIcons.tshirt,
    'speaker': KIcons.speaker,
    'soundbar': KIcons.speaker,
    'paper': KIcons.paper,
    'rice': KIcons.riceCooker,
    'case': KIcons.phoneCase,
  };
  final icon =
      byWord.entries.where((e) => name.contains(e.key)).firstOrNull?.value ??
      KIcons.package;
  final tone = KArtTone
      .values[id.codeUnits.fold(0, (a, b) => a + b) % KArtTone.values.length];
  return KProductArt(icon: icon, tone: tone, radius: radius);
}

/// Category icon keys from A-05 mapped to the K icon set.
KIconData categoryIcon(String? key) => switch (key) {
  'headphones' => KIcons.headphones,
  'watch' => KIcons.watch,
  'shirt' => KIcons.tshirt,
  'bag' => KIcons.backpack,
  'home' || 'sofa' => KIcons.lamp,
  'kitchen' => KIcons.mug,
  'sports' => KIcons.sneaker,
  'office' => KIcons.paper,
  'pantry' => KIcons.bottle,
  'devices' => KIcons.speaker,
  'phone' || 'plug' => KIcons.phoneCase,
  'camera' => KIcons.camera,
  'laptop' => KIcons.dashboard,
  _ => KIcons.categories,
};

/// A stable tint per category so the grid has the design's variety.
KArtTone categoryTone(StoreCategory category) =>
    KArtTone.values[(category.sort + category.slug.length) %
        KArtTone.values.length];

/// A product card for [item]: retail with USD and KHR, or the business card
/// with "Price on quote" and the minimum quantity. [isNew] adds the pill.
class StoreProductCard extends ConsumerWidget {
  const StoreProductCard({
    super.key,
    required this.item,
    required this.role,
    this.isNew = false,
  });

  final BrowseItem item;
  final AppRole role;
  final bool isNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = Localizations.localeOf(context).languageCode;
    final name = item.name.of(lang);
    final image = Stack(
      fit: StackFit.expand,
      children: [
        KNetworkImage(
          url: item.imageUrl,
          semanticLabel: name,
          fallback: productArt(item),
        ),
        if (isNew && !item.soldOut)
          Positioned(
            left: 8,
            bottom: 8,
            child: KStatusPill(
              label: AppLocalizations.of(context).storeNew,
              tone: KTone.violet,
            ),
          ),
      ],
    );
    void open() => context.push(AppRoutes.product(role.homePath, item.id));
    final price = item.priceCents;
    if (role == AppRole.business || price == null) {
      return KProductCard.business(
        name: name,
        image: image,
        minQuantity: item.rfqMinQty?.toString(),
        soldOut: item.soldOut,
        onTap: open,
      );
    }
    final rate = ref.watch(khrRateValueProvider);
    return KProductCard(
      name: name,
      image: image,
      price: formatUsd(price),
      khrAmount: formatKhrAmount(usdCentsToKhr(price, rate)),
      rating: item.ratingCount > 0 ? item.ratingAvg : null,
      ratingCount: item.ratingCount > 0 ? item.ratingCount : null,
      soldOut: item.soldOut,
      onTap: open,
    );
  }
}

/// Section title with an optional "See all".
class StoreSectionHead extends StatelessWidget {
  const StoreSectionHead({super.key, required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
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
          if (onSeeAll != null)
            KButton.ghost(
              label: AppLocalizations.of(context).storeSeeAll,
              size: KButtonSize.sm,
              onPressed: onSeeAll,
            ),
        ],
      ),
    );
  }
}

/// Grid of product cards that fits the width: two columns on phones, more
/// on tablets and the web.
class StoreProductGrid extends StatelessWidget {
  const StoreProductGrid({
    super.key,
    required this.children,
    this.minTileWidth = 160,
  });

  final List<Widget> children;
  final double minTileWidth;

  static int columnsFor(double width, {double minTileWidth = 160}) =>
      (width / (minTileWidth + 12)).floor().clamp(2, 6);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final columns = columnsFor(box.maxWidth, minTileWidth: minTileWidth);
        final width = (box.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final c in children) SizedBox(width: width, child: c),
          ],
        );
      },
    );
  }
}

/// Skeleton cards while a grid or rail loads.
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.k.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(KRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(aspectRatio: 1, child: KSkeleton(radius: 0)),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KSkeleton(height: 14),
                SizedBox(height: 6),
                KSkeleton(width: 80, height: 14),
                SizedBox(height: 10),
                KSkeleton(width: 56, height: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "3:00 PM" for a cut-off.
String cutoffLabel(AppLocalizations l10n, Cutoff cutoff) => formatTime(
  l10n,
  // Wall-clock fields are Phnom Penh time; the formatter takes an instant.
  DateTime.utc(
    2000,
    1,
    1,
    cutoff.hour,
    cutoff.minute,
  ).subtract(phnomPenhOffset),
);

/// The same-day promise (C-01, C-02): "Order within 4h 35m for delivery
/// today", or when the next delivery day is once today's cut-off has passed.
/// Follows the server clock; refreshes every 30 seconds.
class SameDayBanner extends ConsumerStatefulWidget {
  const SameDayBanner({super.key, this.compact = false});

  /// The C-02 line ("Delivered today if you order before 3 PM").
  final bool compact;

  @override
  ConsumerState<SameDayBanner> createState() => _SameDayBannerState();
}

class _SameDayBannerState extends ConsumerState<SameDayBanner> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final deviceNow = ref.watch(clockProvider)();
    final clock =
        ref.watch(storeClockProvider).value ?? StoreClock.local(deviceNow);
    final status = SameDayStatus.at(clock.nowFrom(deviceNow), clock);
    final cutoff = cutoffLabel(l10n, clock.cutoff);
    final bold = k.text.small.copyWith(fontWeight: FontWeight.w800);
    final InlineSpan span = switch (status) {
      SameDayOpen() when widget.compact => TextSpan(
        text: l10n.storeSameDayBefore(cutoff),
      ),
      SameDayOpen(:final remaining) => TextSpan(
        children: [
          TextSpan(text: l10n.storeOrderWithinPrefix),
          TextSpan(text: durationLabel(l10n, remaining), style: bold),
          TextSpan(text: l10n.storeOrderWithinSuffix),
        ],
      ),
      SameDayClosed(isTomorrow: true) => TextSpan(
        text: l10n.storeCutoffPassedTomorrow(cutoff),
      ),
      SameDayClosed(:final nextDay) => TextSpan(
        text: l10n.storeCutoffPassedOn(
          formatShortDate(l10n, nextDay.subtract(phnomPenhOffset)),
        ),
      ),
    };
    return KBanner.rich(
      key: const Key('same-day-banner'),
      span: span,
      icon: widget.compact ? KIcons.delivery : KIcons.time,
    );
  }
}
