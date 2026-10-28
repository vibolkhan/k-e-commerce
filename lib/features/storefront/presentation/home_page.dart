import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/bootstrap.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/router/app_role.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/ui/k_ui.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../notifications/presentation/notification_bell.dart';
import '../../shell/presentation/role_home_page.dart' show DevRoleSwitcher;
import '../domain/browse.dart';
import '../domain/storefront.dart';
import 'deliver_to_sheet.dart';
import 'store_widgets.dart';
import 'storefront_providers.dart';

/// Content stops growing past this on wide screens (web).
const storeMaxWidth = 1200.0;

/// C-01 Home (B-00 for business buyers): location pill, search, banners,
/// the same-day countdown, categories, the featured collection, the
/// business-buyer promo and new arrivals. Each section loads on its own
/// with a skeleton and disappears when it has nothing to show.
class HomePage extends ConsumerWidget {
  const HomePage({super.key, required this.role});

  final AppRole role;

  bool get _business => role == AppRole.business;
  Audience get _audience => _business ? Audience.business : Audience.retail;

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(storeCategoriesProvider)
      ..invalidate(homeBannersProvider)
      ..invalidate(collectionRailProvider)
      ..invalidate(storeClockProvider);
    await ref.read(storeCategoriesProvider.future).catchError((_) {
      return CategoryTree(const []);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final k = context.k;
    final shell = role.homePath;
    final featured = HomeCollections.featured(_audience);
    final configured = ref.watch(appConfigProvider).isSupabaseConfigured;
    return Scaffold(
      key: ValueKey('store-home-${role.name}'),
      backgroundColor: k.colors.bg,
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _HomeHeader(role: role)),
            SliverToBoxAdapter(
              child: _Centered(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!configured) ...[
                      const SizedBox(height: 16),
                      KBanner(
                        message: l10n.supabaseNotConfigured,
                        tone: KBannerTone.warn,
                      ),
                    ],
                    const SizedBox(height: 16),
                    _BannerCarousel(role: role, audience: _audience),
                    const SizedBox(height: 12),
                    if (_business)
                      KBanner(message: l10n.storeBusinessPricesNote)
                    else
                      const SameDayBanner(),
                    StoreSectionHead(
                      title: l10n.storeShopByCategory,
                      onSeeAll: () => context.go(AppRoutes.categories(shell)),
                    ),
                    _CategoryShortcuts(role: role),
                    _CollectionSection(
                      role: role,
                      slug: featured,
                      title: _business
                          ? l10n.storePopularForOffices
                          : l10n.storeBestSellers,
                      rail: !_business,
                    ),
                    if (!_business) ...[
                      const SizedBox(height: 16),
                      _BusinessPromo(role: role),
                    ],
                    _CollectionSection(
                      role: role,
                      slug: HomeCollections.newArrivals,
                      title: l10n.storeNewArrivals,
                      rail: false,
                      isNew: true,
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 32),
                      DevRoleSwitcher(current: role),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal padding, and a max width on wide screens.
class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: storeMaxWidth),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: child,
      ),
    ),
  );
}

class _HomeHeader extends ConsumerWidget {
  const _HomeHeader({required this.role});
  final AppRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final signedIn = ref.watch(currentProfileProvider).value != null;
    return Material(
      color: k.colors.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: k.colors.line)),
          ),
          child: _Centered(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    const ExcludeSemantics(child: KLogo(size: 36)),
                    const SizedBox(width: 12),
                    Expanded(child: _LocationPill(role: role)),
                    if (signedIn) NotificationBell(shell: role.homePath),
                  ],
                ),
                const SizedBox(height: 8),
                KTextField.search(
                  key: const Key('home-search'),
                  hint: role == AppRole.business
                      ? l10n.storeSearchHintBusiness
                      : l10n.storeSearchHint,
                  readOnly: true,
                  onTap: () => context.push(AppRoutes.search(role.homePath)),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Deliver to · Home · Toul Kork"; the city for guests.
class _LocationPill extends ConsumerWidget {
  const _LocationPill({required this.role});
  final AppRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = context.k;
    final l10n = AppLocalizations.of(context);
    final to = ref.watch(deliverToProvider(watchViewer(ref)));
    final place = to == null
        ? l10n.storeDefaultCity
        : [to.label, ?to.area].join(' · ');
    return Semantics(
      button: true,
      label: l10n.storeDeliverToLabel(place),
      excludeSemantics: true,
      child: InkWell(
        key: const Key('deliver-to'),
        borderRadius: BorderRadius.circular(KRadius.input),
        onTap: () => showDeliverToSheet(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinTap),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.storeDeliverTo,
                style: k.text.caption.copyWith(color: k.colors.muted),
              ),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      place,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: k.text.body.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 4),
                  KIcon(KIcons.chevronDown, size: 16, color: k.colors.ink2),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _bannerHeight = 200.0;

/// Promo banners (CAT-06), swiping and advancing every 6 seconds. With no
/// live banners the same-day hero from the design stands in.
class _BannerCarousel extends ConsumerStatefulWidget {
  const _BannerCarousel({required this.role, required this.audience});

  final AppRole role;
  final Audience audience;

  @override
  ConsumerState<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends ConsumerState<_BannerCarousel> {
  final _pages = PageController();
  Timer? _auto;
  int _autoCount = 0;
  int _index = 0;

  @override
  void dispose() {
    _auto?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _restartAuto(int count) {
    _auto?.cancel();
    if (count < 2) return;
    _auto = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!_pages.hasClients) return;
      _pages.animateToPage(
        (_index + 1) % count,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  void _open(HomeBanner banner) {
    final shell = widget.role.homePath;
    final target = banner.linkTarget;
    if (target == null || target.isEmpty) return;
    switch (banner.linkType) {
      case BannerLinkType.collection:
        context.push(AppRoutes.collection(shell, target));
      case BannerLinkType.category:
        context.push(AppRoutes.category(shell, target));
      case BannerLinkType.product:
        context.push(AppRoutes.product(shell, target));
      // Static pages and links arrive with A-12 / F14.
      case BannerLinkType.page || BannerLinkType.url || null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final banners = ref.watch(
      homeBannersProvider((
        audience: widget.audience,
        viewer: watchViewer(ref),
      )),
    );
    final list = banners.value ?? const <HomeBanner>[];
    if (banners.isLoading && !banners.hasValue) {
      return const KSkeleton(height: _bannerHeight, radius: 20);
    }
    if (list.isEmpty) return const SizedBox.shrink();
    if (_autoCount != list.length) {
      _autoCount = list.length;
      _restartAuto(list.length);
    }
    return Column(
      children: [
        SizedBox(
          height: _bannerHeight,
          child: PageView.builder(
            controller: _pages,
            itemCount: list.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _BannerCard(banner: list[i], onTap: () => _open(list[i])),
            ),
          ),
        ),
        if (list.length > 1) ...[
          const SizedBox(height: 8),
          _Dots(count: list.length, index: _index),
        ],
      ],
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.banner, required this.onTap});

  final HomeBanner banner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final lang = Localizations.localeOf(context).languageCode;
    final badge = banner.badge.of(lang);
    final subtitle = banner.subtitle.of(lang);
    final cta = banner.cta.of(lang);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Material(
        color: k.colors.primary,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (banner.imageUrl != null)
                KNetworkImage(
                  url: banner.imageUrl,
                  fallback: const SizedBox.shrink(),
                ),
              Positioned(
                right: -24,
                bottom: -24,
                child: ExcludeSemantics(
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .12),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const KIcon(
                      KIcons.delivery,
                      size: 64,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              // Long titles (Khmer, large text) shrink instead of
              // overflowing the fixed-height card.
              Padding(
                padding: const EdgeInsets.all(20),
                child: LayoutBuilder(
                  builder: (context, box) => FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: box.maxWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (badge.isNotEmpty) ...[
                            KStatusPill(label: badge, tone: KTone.white),
                            const SizedBox(height: 8),
                          ],
                          Padding(
                            padding: const EdgeInsets.only(right: 96),
                            child: Text(
                              banner.title.of(lang),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: k.text.h2.copyWith(
                                fontSize: 22,
                                height: 28 / 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.only(right: 96),
                              child: Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: k.text.small.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                          if (cta.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            ExcludeSemantics(
                              child: Container(
                                height: 36,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(
                                    KRadius.buttonSm,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  cta,
                                  style: k.text.label.copyWith(
                                    color: k.colors.primaryInk,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.k.colors;
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == index ? c.primary : c.line2,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Shop by category": 4 per row on phones, 8 on wide screens.
class _CategoryShortcuts extends ConsumerWidget {
  const _CategoryShortcuts({required this.role});
  final AppRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(storeCategoriesProvider);
    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth >= 600 ? 8 : 4;
        final width = (box.maxWidth - (columns - 1) * 8) / columns;
        final Widget content;
        if (tree.isLoading && !tree.hasValue) {
          content = Wrap(
            spacing: 8,
            runSpacing: 12,
            children: [
              for (var i = 0; i < columns * 2; i++)
                SizedBox(
                  width: width,
                  child: const Column(
                    children: [
                      KSkeleton(width: 64, height: 64, radius: 20),
                      SizedBox(height: 6),
                      KSkeleton(width: 48),
                    ],
                  ),
                ),
            ],
          );
        } else {
          final items = tree.value?.shortcuts(columns * 2) ?? const [];
          if (items.isEmpty) return const SizedBox.shrink();
          content = Wrap(
            spacing: 8,
            runSpacing: 12,
            children: [
              for (final c in items)
                SizedBox(
                  width: width,
                  child: CategoryTile(
                    category: c,
                    onTap: () =>
                        context.go(AppRoutes.category(role.homePath, c.slug)),
                  ),
                ),
            ],
          );
        }
        return content;
      },
    );
  }
}

/// Tinted icon square with the name under it (C-01, C-02).
class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required this.category,
    required this.onTap,
    this.size = 64,
  });

  final StoreCategory category;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final lang = Localizations.localeOf(context).languageCode;
    final name = category.name.of(lang);
    final (bg, fg) = KProductArt.colorsFor(categoryTone(category));
    return Semantics(
      button: true,
      label: name,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(KRadius.box),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(size * 0.3),
                ),
                alignment: Alignment.center,
                child: KIcon(categoryIcon(category.icon), size: 28, color: fg),
              ),
              const SizedBox(height: 6),
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: k.text.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: k.colors.ink2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A collection as a horizontal rail ([rail]) or a grid.
class _CollectionSection extends ConsumerWidget {
  const _CollectionSection({
    required this.role,
    required this.slug,
    required this.title,
    required this.rail,
    this.isNew = false,
  });

  final AppRole role;
  final String slug;
  final String title;
  final bool rail;
  final bool isNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(
      collectionRailProvider((slug: slug, viewer: watchViewer(ref))),
    );
    final loading = items.isLoading && !items.hasValue;
    final list = items.value ?? const <BrowseItem>[];
    if (!loading && list.isEmpty) return const SizedBox.shrink();
    final cards = loading
        ? [for (var i = 0; i < 4; i++) const ProductCardSkeleton()]
        : [
            for (final item in list)
              StoreProductCard(item: item, role: role, isNew: isNew),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StoreSectionHead(
          title: title,
          onSeeAll: () =>
              context.push(AppRoutes.collection(role.homePath, slug)),
        ),
        if (rail)
          SingleChildScrollView(
            key: Key('rail-$slug'),
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, c) in cards.indexed) ...[
                  if (i > 0) const SizedBox(width: 12),
                  SizedBox(width: 156, child: c),
                ],
              ],
            ),
          )
        else
          StoreProductGrid(children: cards.take(6).toList()),
      ],
    );
  }
}

/// "Buying for a business?" tile for guests and customers.
class _BusinessPromo extends StatelessWidget {
  const _BusinessPromo({required this.role});
  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: '${l10n.storeBusinessPromoTitle}. ${l10n.storeBusinessPromoBody}',
      excludeSemantics: true,
      child: Material(
        color: c.tint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KRadius.card),
          side: BorderSide(color: c.tintLine),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('business-promo'),
          onTap: () => context.push(AppRoutes.businessUpgrade(role.homePath)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(KRadius.input),
                  ),
                  alignment: Alignment.center,
                  child: KIcon(KIcons.business, color: c.primaryInk),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.storeBusinessPromoTitle,
                        style: k.text.body.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.storeBusinessPromoBody,
                        style: k.text.small.copyWith(color: c.ink2),
                      ),
                    ],
                  ),
                ),
                KIcon(KIcons.chevronRight, color: c.ink2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
