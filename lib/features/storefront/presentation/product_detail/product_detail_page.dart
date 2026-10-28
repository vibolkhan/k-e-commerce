import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/l10n/generated/app_localizations.dart';
import '../../../../core/money/money_format.dart';
import '../../../../core/router/app_role.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/ui/k_ui.dart';
import '../../../../core/ui/pages/error_page.dart';
import '../../../auth/domain/auth_intent.dart';
import '../../../auth/presentation/require_sign_in.dart';
import '../../../cart/presentation/cart_providers.dart';
import '../../domain/product_detail.dart';
import '../store_widgets.dart';
import '../storefront_providers.dart';
import 'choose_options_sheet.dart';
import 'image_viewer_page.dart';
import 'pd_tabs.dart';
import 'pd_widgets.dart';
import 'product_detail_providers.dart';

/// C-05 product detail for guests and customers: gallery, stock, rating,
/// price in USD and KHR, variants, delivery, the three tabs (C-05, C-05a,
/// C-05b) and "You may also like". Add to cart opens C-05c and confirms
/// with the C-05d toast.
class ProductDetailPage extends ConsumerWidget {
  const ProductDetailPage({super.key, required this.role, required this.id});

  final AppRole role;
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(
      productDetailProvider((id: id, viewer: watchViewer(ref))),
    );
    return switch (detail) {
      AsyncData(value: final product?) => _ProductView(
        key: ValueKey(product.id),
        role: role,
        product: product,
      ),
      AsyncData() => const ErrorPage.notFound(),
      // Also while Riverpod retries in the background, so a failed read
      // doesn't sit on the skeleton.
      AsyncValue(hasError: true) => Scaffold(
        appBar: const KAppBar(),
        body: Center(
          child: KEmptyState(
            icon: KIcons.error,
            title: l10n.storeLoadFailed,
            action: KButton.outline(
              label: l10n.storeRetry,
              onPressed: () => ref.invalidate(
                productDetailProvider((id: id, viewer: watchViewer(ref))),
              ),
            ),
          ),
        ),
      ),
      _ => const _ProductSkeleton(),
    };
  }
}

/// Content is no wider than this on tablets and the web.
const _maxContentWidth = 720.0;

class _ProductView extends ConsumerStatefulWidget {
  const _ProductView({super.key, required this.role, required this.product});

  final AppRole role;
  final ProductDetail product;

  @override
  ConsumerState<_ProductView> createState() => _ProductViewState();
}

class _ProductViewState extends ConsumerState<_ProductView> {
  late VariantSelection _selection = VariantSelection.initial(widget.product);
  PdTab _tab = PdTab.description;
  int _photo = 0;
  bool _solidBar = false;
  final _scroll = ScrollController();
  final _gallery = PageController();
  final _tabsKey = GlobalKey();

  ProductDetail get _product => widget.product;

  double _galleryHeight(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width.clamp(0, _maxContentWidth);
    return width < 390 ? width * 360 / 390 : 360;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final solid = _scroll.offset > _galleryHeight(context) - 56;
      if (solid != _solidBar) setState(() => _solidBar = solid);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _gallery.dispose();
    super.dispose();
  }

  void _select(VariantSelection next) {
    setState(() => _selection = next);
    final variant = next.variant;
    final photo = variant == null ? null : _product.imageIndexFor(variant);
    if (photo != null && photo != _photo && _gallery.hasClients) {
      _gallery.animateToPage(
        photo,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  void _showReviews() {
    setState(() => _tab = PdTab.reviews);
    final target = _tabsKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 250),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    }
  }

  String? get _shareUrl => kIsWeb
      ? Uri.base
            .replace(path: AppRoutes.product(widget.role.homePath, _product.id))
            .replace(query: '')
            .toString()
            .replaceFirst(RegExp(r'\?$'), '')
      : null;

  void _openViewer() => Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => ImageViewerPage(
        productId: _product.id,
        initialIndex: _photo,
        shareUrl: _shareUrl,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );

  Future<void> _wishlist() async {
    final l10n = AppLocalizations.of(context);
    if (!await requireSignIn(context, ref, AuthIntent.wishlist)) return;
    if (!mounted) return;
    // The real toggle is F32.
    showKToast(context, message: l10n.pdWishlistSoon, tone: KToastTone.info);
  }

  Future<void> _addToCart() async {
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final added = await showChooseOptions(
      context,
      selection: _selection,
      onSelection: _select,
    );
    if (added == null || !mounted) return;
    final name = _product.name.of(lang);
    final label = added.variant.label;
    final cart = AppRoutes.cart(widget.role.homePath);
    showKToast(
      context,
      message: l10n.pdAddedToCart,
      detail: label.isEmpty
          ? l10n.pdAddedDetailPlain(name, added.qty)
          : l10n.pdAddedDetail(name, label, added.qty),
      actionLabel: l10n.pdViewCart,
      onAction: () => context.push(cart),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final variant = _selection.variant;
    final name = _product.name.of(lang);
    final galleryHeight = _galleryHeight(context);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Gallery(
          product: _product,
          height: galleryHeight,
          controller: _gallery,
          index: _photo,
          onChanged: (i) => setState(() => _photo = i),
          onOpen: _openViewer,
        ),
        Padding(
          padding: const EdgeInsets.all(KSpacing.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PdStockLine(stock: variant?.stock ?? const OutOfStock()),
              const SizedBox(height: 10),
              Semantics(header: true, child: Text(name, style: k.text.h1)),
              const SizedBox(height: 10),
              _RatingLink(product: _product, onTap: _showReviews),
              const SizedBox(height: 10),
              if (variant?.priceCents != null)
                KPrice(key: const Key('pd-price'), cents: variant!.priceCents!),
              const SizedBox(height: 4),
              Text(
                l10n.pdVatIncluded,
                style: k.text.caption.copyWith(color: c.muted),
              ),
              if (_product.axes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Divider(height: 1, color: c.line),
                const SizedBox(height: 16),
                PdOptionPicker(selection: _selection, onChanged: _select),
              ],
              const SizedBox(height: 16),
              PdDeliveryCard(product: _product),
            ],
          ),
        ),
        KTabs(
          key: _tabsKey,
          fill: true,
          tabs: [
            KTab(l10n.pdTabDescription),
            KTab(l10n.pdTabSpecs),
            KTab(
              l10n.pdTabReviews,
              count: _product.ratingCount > 0 ? _product.ratingCount : null,
            ),
          ],
          selectedIndex: _tab.index,
          onChanged: (i) => setState(() => _tab = PdTab.values[i]),
        ),
        Padding(
          padding: const EdgeInsets.all(KSpacing.gutter),
          child: pdTabPanel(_tab, _product),
        ),
        if (_product.related.isNotEmpty) ...[
          Container(height: 8, color: c.bg),
          PdRelatedRow(product: _product, role: widget.role),
          const SizedBox(height: 16),
        ],
      ],
    );

    return Scaffold(
      backgroundColor: c.surface,
      body: Stack(
        children: [
          SingleChildScrollView(
            key: const Key('pd-scroll'),
            controller: _scroll,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                child: content,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _TopBar(
              title: name,
              solid: _solidBar,
              shareUrl: _shareUrl,
              home: widget.role.homePath,
            ),
          ),
        ],
      ),
      bottomNavigationBar: _ActionBar(
        price: _tab == PdTab.description ? null : variant?.priceCents,
        soldOut: _product.soldOut,
        onWishlist: _wishlist,
        onAdd: _addToCart,
      ),
    );
  }
}

/// Back, Share and the cart over the gallery; a white bar with the title
/// once the gallery has scrolled away (C-05a, C-05b).
class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.title,
    required this.solid,
    required this.shareUrl,
    required this.home,
  });

  final String title;
  final bool solid;
  final String? shareUrl;

  /// The shell's home, for Back when there is nothing to pop (web reload).
  final String home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final count = ref.watch(cartCountProvider);
    final style = solid ? KIconButtonStyle.plain : KIconButtonStyle.white;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: solid ? c.surface : Colors.transparent,
        border: Border(
          bottom: BorderSide(color: solid ? c.line : Colors.transparent),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              KIconButton(
                icon: KIcons.back,
                label: MaterialLocalizations.of(context).backButtonTooltip,
                style: style,
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go(home),
              ),
              const SizedBox(width: 8),
              Expanded(
                // Hidden over the gallery, where taps belong to the photos.
                child: IgnorePointer(
                  ignoring: !solid,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: solid ? 1 : 0,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: k.text.body.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              if (shareUrl != null) ...[
                KIconButton(
                  icon: KIcons.share,
                  label: l10n.pdShare,
                  style: style,
                  onPressed: () => copyProductLink(context, shareUrl!),
                ),
                const SizedBox(width: 8),
              ],
              KIconButton(
                key: const Key('pd-cart'),
                icon: KIcons.cart,
                label: l10n.pdCartA11y(count),
                style: style,
                badge: count,
                onPressed: () => context.push(AppRoutes.cart(home)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery({
    required this.product,
    required this.height,
    required this.controller,
    required this.index,
    required this.onChanged,
    required this.onOpen,
  });

  final ProductDetail product;
  final double height;
  final PageController controller;
  final int index;
  final ValueChanged<int> onChanged;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.k.colors;
    final l10n = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final slides = pdSlideCount(product);
    final art = productArtFor(product.id, product.name.en);
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: controller,
              itemCount: slides,
              onPageChanged: onChanged,
              itemBuilder: (_, i) => GestureDetector(
                onTap: onOpen,
                child: product.images.isEmpty
                    ? art
                    : KNetworkImage(
                        url: product.images[i].url,
                        semanticLabel: product.images[i].alt.isEmpty
                            ? product.name.of(lang)
                            : product.images[i].alt.of(lang),
                        fallback: art,
                      ),
              ),
            ),
          ),
          if (slides > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 14,
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < slides; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == index ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == index ? c.primary : KColors.line2,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Positioned(
            right: 12,
            bottom: 10,
            child: Semantics(
              button: true,
              label: l10n.pdOpenPhotos(index + 1, slides),
              excludeSemantics: true,
              onTap: onOpen,
              child: Material(
                color: c.surface,
                shape: const StadiumBorder(),
                elevation: 1,
                child: InkWell(
                  key: const Key('pd-open-viewer'),
                  customBorder: const StadiumBorder(),
                  onTap: onOpen,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        KIcon(KIcons.image, size: 16, color: c.ink),
                        const SizedBox(width: 6),
                        Text(
                          l10n.pdPhotoCounter(index + 1, slides),
                          style: context.k.text.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stars, "4.6" and "128 reviews" in primary; opens the Reviews tab.
class _RatingLink extends StatelessWidget {
  const _RatingLink({required this.product, required this.onTap});

  final ProductDetail product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = k.colors;
    final l10n = AppLocalizations.of(context);
    final avg = product.ratingAvg.toStringAsFixed(1);
    return Semantics(
      button: true,
      label: l10n.pdRatingA11y(avg, product.ratingCount),
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        key: const Key('pd-rating'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(KRadius.tag),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 28),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              KStars(rating: product.ratingAvg, size: 16),
              if (product.ratingCount > 0) ...[
                const SizedBox(width: 8),
                Text(
                  avg,
                  style: k.text.small.copyWith(
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Text(
                l10n.pdReviewCount(product.ratingCount),
                style: k.text.small.copyWith(
                  fontWeight: FontWeight.w700,
                  color: c.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The heart and "Add to cart" (with the price on C-05a and C-05b).
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.price,
    required this.soldOut,
    required this.onWishlist,
    required this.onAdd,
  });

  final int? price;
  final bool soldOut;
  final VoidCallback onWishlist;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.k.colors;
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  KIconButton(
                    key: const Key('pd-wishlist'),
                    icon: KIcons.heart,
                    label: l10n.pdSaveWishlist,
                    style: KIconButtonStyle.outline,
                    onPressed: onWishlist,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: KButton(
                      key: const Key('pd-add'),
                      label: soldOut
                          ? l10n.pdSoldOut
                          : price == null
                          ? l10n.pdAddToCart
                          : l10n.pdAddToCartPrice(formatUsd(price!)),
                      icon: KIcons.cart,
                      size: KButtonSize.lg,
                      expand: true,
                      onPressed: soldOut ? null : onAdd,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductSkeleton extends StatelessWidget {
  const _ProductSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: KAppBar(),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 300, child: KSkeleton(radius: 0)),
            Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KSkeleton(width: 80, height: 24),
                  SizedBox(height: 12),
                  KSkeleton(height: 28),
                  SizedBox(height: 12),
                  KSkeleton(width: 160, height: 16),
                  SizedBox(height: 12),
                  KSkeleton(width: 120, height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
