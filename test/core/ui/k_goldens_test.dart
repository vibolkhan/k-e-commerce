@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/core/domain/statuses.dart';
import 'package:k_e_commerce/core/ui/k_ui.dart';

import '../../helpers.dart';

/// Phone-width goldens for the main components. Update with
/// `flutter test --update-goldens --tags golden` (on Windows).
void main() {
  Future<void> golden(
    WidgetTester tester,
    String name,
    Widget child, {
    double height = 600,
    Locale locale = const Locale('en'),
  }) async {
    setViewSize(tester, Size(390, height));
    await withRealShadows(() async {
      await tester.pumpWidget(
        localized(
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
          locale: locale,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/$name.png'),
      );
    });
  }

  Widget gap(List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, c) in children.indexed) ...[
        if (i > 0) const SizedBox(height: 12),
        c,
      ],
    ],
  );

  void none() {}

  testWidgets('buttons', (tester) async {
    await golden(
      tester,
      'buttons',
      gap([
        KButton(label: 'Primary · Place order', onPressed: none, expand: true),
        KButton.tonal(label: 'Tonal · Add to quote', onPressed: none),
        KButton.outline(label: 'Outline', onPressed: none),
        Row(
          children: [
            KButton.ghost(label: 'Ghost', onPressed: none),
            const SizedBox(width: 12),
            KButton.danger(label: 'Delete', onPressed: none),
            const SizedBox(width: 12),
            KButton(
              label: 'Cancel order',
              variant: KButtonVariant.dangerOutline,
              onPressed: none,
            ),
          ],
        ),
        Row(
          children: [
            const KButton(label: 'Disabled', onPressed: null),
            const SizedBox(width: 12),
            KButton(
              label: 'Place order',
              loadingLabel: 'Placing…',
              loading: true,
              onPressed: none,
            ),
          ],
        ),
        Row(
          children: [
            KButton(label: 'Large', size: KButtonSize.lg, onPressed: none),
            const SizedBox(width: 12),
            KButton(label: 'Medium', onPressed: none),
            const SizedBox(width: 12),
            KButton(label: 'Small', size: KButtonSize.sm, onPressed: none),
          ],
        ),
      ]),
      height: 460,
    );
  });

  testWidgets('fields', (tester) async {
    await golden(
      tester,
      'fields',
      gap([
        const KTextField(
          label: 'Phone number',
          prefixText: '+855',
          initialValue: '12 345 678',
        ),
        const KTextField(
          label: 'VAT TIN',
          initialValue: 'K001-10023',
          errorText: 'Enter the full 14-character TIN',
        ),
        const KTextField(
          label: 'Note to rider',
          optional: true,
          hint: 'Gate code, landmark',
          helpText: 'Riders see this note.',
          maxLines: 3,
        ),
        const KTextField.search(hint: 'Search products'),
        const KTextField(
          label: 'Phone (verified)',
          initialValue: '+855 12 345 678',
          enabled: false,
        ),
        const KOtpField(error: true),
      ]),
      height: 680,
    );
  });

  testWidgets('selection', (tester) async {
    await golden(
      tester,
      'selection',
      gap([
        Wrap(
          spacing: 8,
          children: [
            KChip(label: 'All', selected: true, onTap: none),
            KChip(label: 'Audio', onTap: none),
            KChip(label: 'Filters', icon: KIcons.filter, count: 2, onTap: none),
          ],
        ),
        KSegmented<int>(
          segments: const [KSegment(0, 'Phone'), KSegment(1, 'Email')],
          selected: 0,
          onChanged: (_) {},
        ),
        KTabs(
          selectedIndex: 0,
          onChanged: (_) {},
          fill: true,
          tabs: const [KTab('Active', count: 2), KTab('Done'), KTab('Off')],
        ),
        KOptionTile(
          title: 'KHQR',
          subtitle: 'Pay with any Cambodian banking app',
          icon: KIcons.khqr,
          selected: true,
          onTap: none,
        ),
        KOptionTile(
          title: 'Cash on delivery',
          subtitle: 'Pay the rider when it arrives',
          icon: KIcons.cash,
          selected: false,
          onTap: none,
        ),
      ]),
      height: 420,
    );
  });

  testWidgets('status pills', (tester) async {
    Widget wrap(List<Widget> pills) =>
        Wrap(spacing: 8, runSpacing: 8, children: pills);
    await golden(
      tester,
      'status_pills',
      gap([
        wrap([for (final s in OrderStatus.values) KStatusPill.order(s)]),
        wrap([for (final s in PaymentStatus.values) KStatusPill.payment(s)]),
        wrap([for (final s in QuoteStatus.values) KStatusPill.quote(s)]),
      ]),
      height: 360,
    );
  });

  testWidgets('status pills in Khmer', (tester) async {
    await golden(
      tester,
      'status_pills_km',
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final s in OrderStatus.values) KStatusPill.order(s)],
      ),
      height: 200,
      locale: const Locale('km'),
    );
  });

  testWidgets('product cards', (tester) async {
    await golden(
      tester,
      'product_cards',
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: KProductCard(
              name: 'Wireless Headphones Pro',
              image: const KProductArt(icon: KIcons.headphones, radius: 0),
              price: r'$49.00',
              khrAmount: '200,900',
              rating: 4.6,
              ratingCount: 128,
              wishlisted: true,
              onWishlist: none,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: KProductCard.business(
              name: 'A4 Copy Paper, 80 gsm (500 sheets)',
              image: KProductArt(
                icon: KIcons.paper,
                tone: KArtTone.c,
                radius: 0,
              ),
              minQuantity: '20 reams',
              rating: 4.7,
              ratingCount: 64,
              soldOut: true,
            ),
          ),
        ],
      ),
      height: 360,
    );
  });

  testWidgets('content', (tester) async {
    await golden(
      tester,
      'content',
      gap([
        const KCard(
          padding: EdgeInsets.zero,
          clip: true,
          child: KList(
            children: [
              KListRow(
                icon: KIcons.location,
                title: 'Addresses',
                subtitle: '2 saved · Home is default',
                onTap: _noop,
              ),
              KListRow(
                icon: KIcons.language,
                title: 'Language',
                subtitle: 'English',
                onTap: _noop,
              ),
            ],
          ),
        ),
        Row(
          children: [
            const Expanded(child: KStars(rating: 4)),
            KQtyStepper(value: 1, onChanged: (_) {}),
          ],
        ),
        const KTimeline(
          steps: [
            KTimelineStep(
              title: 'Order placed',
              subtitle: 'Today, 10:24 AM',
              state: KStepState.done,
            ),
            KTimelineStep(title: 'Packing', state: KStepState.now),
            KTimelineStep(title: 'Failed delivery', state: KStepState.bad),
            KTimelineStep(title: 'Delivered', state: KStepState.todo),
          ],
        ),
        const KBanner(message: 'Order within 4h 35m for delivery today.'),
        const KBanner(
          tone: KBannerTone.warn,
          message: r'Return delivery ($2.00) is paid by you.',
        ),
        const KBanner(tone: KBannerTone.bad, message: 'Out of stock.'),
        const KBanner(tone: KBannerTone.ok, message: 'Payment received.'),
        const KEmptyState(
          compact: true,
          icon: KIcons.heart,
          title: 'No saved items yet',
          message: 'Tap the heart on any product to save it here.',
        ),
      ]),
      height: 1000,
    );
  });

  testWidgets('navigation', (tester) async {
    await golden(
      tester,
      'navigation',
      Builder(
        builder: (c) => MediaQuery.removePadding(
          context: c,
          removeBottom: true,
          child: gap([
            KAppBar(title: 'Checkout', showBack: true, onBack: none),
            KAppBar(
              title: 'Audio',
              centerTitle: false,
              showBack: true,
              onBack: none,
              actions: [
                KIconButton(
                  icon: KIcons.cart,
                  label: 'Cart, 3 items',
                  badge: 3,
                  onPressed: none,
                ),
              ],
            ),
            KBottomNav.customer(
              c,
              currentIndex: 0,
              cartCount: 3,
              onTap: (_) {},
            ),
            KBottomNav.business(
              c,
              currentIndex: 2,
              quoteListCount: 4,
              onTap: (_) {},
            ),
            KBottomNav.guest(c, currentIndex: 3, onTap: (_) {}),
            KBottomNav.rider(c, currentIndex: 0, jobCount: 4, onTap: (_) {}),
            KBottomNav.admin(
              c,
              currentIndex: 0,
              orderCount: 12,
              chatCount: 2,
              onTap: (_) {},
            ),
            const Row(
              children: [
                KLogo(size: 40),
                SizedBox(width: 12),
                KAppIcon(size: 56),
              ],
            ),
          ]),
        ),
      ),
      height: 700,
    );
  });

  testWidgets('overlays', (tester) async {
    await golden(
      tester,
      'overlays',
      gap([
        KConfirmDialog(
          icon: KIcons.time,
          title: 'Leave payment?',
          message: 'Your order is held for 14:32.',
          cancelLabel: 'Leave',
          confirmLabel: 'Stay and pay',
          onCancel: none,
          onConfirm: none,
        ),
        KConfirmDialog(
          tone: KConfirmTone.destructive,
          title: 'Remove from cart?',
          message: 'Wireless Headphones Pro will be removed from your cart.',
          cancelLabel: 'Keep it',
          confirmLabel: 'Remove',
          alternativeLabel: 'Move to wishlist instead',
          onCancel: none,
          onConfirm: none,
          onAlternative: none,
        ),
        KBottomSheet(
          title: 'Sort by',
          onClose: none,
          child: const Text('Most popular'),
        ),
        KToast(
          message: 'Added to cart',
          actionLabel: 'View cart',
          onAction: none,
        ),
        const KToast(message: 'No connection.', tone: KToastTone.bad),
      ]),
      height: 1000,
    );
  });
}

void _noop() {}
