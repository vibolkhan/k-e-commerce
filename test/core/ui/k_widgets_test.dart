import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/core/domain/statuses.dart';
import 'package:k_e_commerce/core/ui/k_ui.dart';

import '../../helpers.dart';

void main() {
  group('KButton', () {
    testWidgets('taps when enabled', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        kHarness(KButton(label: 'Place order', onPressed: () => taps++)),
      );
      await tester.tap(find.text('Place order'));
      expect(taps, 1);
    });

    testWidgets('loading shows spinner and ignores taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        kHarness(
          KButton(
            label: 'Place order',
            loadingLabel: 'Placing…',
            loading: true,
            onPressed: () => taps++,
          ),
        ),
      );
      expect(find.text('Placing…'), findsOneWidget);
      expect(find.byType(KSpinner), findsOneWidget);
      await tester.tap(find.byType(KButton));
      expect(taps, 0);
    });

    testWidgets('disabled is announced as disabled', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        kHarness(const KButton(label: 'Disabled', onPressed: null)),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Disabled')),
        matchesSemantics(
          label: 'Disabled',
          isButton: true,
          hasEnabledState: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('small button keeps a 44 px tap target', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        kHarness(
          const KButton(label: 'Track', size: KButtonSize.sm, onPressed: _noop),
        ),
      );
      expect(tester.getSize(find.byType(KButton)).height, 44);
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      handle.dispose();
    });
  });

  group('KTextField', () {
    testWidgets('shows error instead of help, plus optional label', (
      tester,
    ) async {
      await tester.pumpWidget(
        kHarness(
          const Column(
            children: [
              KTextField(
                label: 'VAT TIN',
                errorText: 'Enter the full TIN',
                helpText: 'Help',
              ),
              KTextField(label: 'Note', optional: true, helpText: 'Shown'),
            ],
          ),
        ),
      );
      expect(find.text('Enter the full TIN'), findsOneWidget);
      expect(find.text('Help'), findsNothing);
      expect(find.text('Shown'), findsOneWidget);
      expect(
        find.textContaining('(optional)', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('label is part of the field semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(kHarness(const KTextField(label: 'Full name')));
      expect(find.bySemanticsLabel(RegExp('Full name')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('prefix segment and typing', (tester) async {
      String? value;
      await tester.pumpWidget(
        kHarness(
          KTextField(
            label: 'Phone',
            prefixText: '+855',
            onChanged: (v) => value = v,
          ),
        ),
      );
      expect(find.text('+855'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '12345678');
      expect(value, '12345678');
    });
  });

  group('KOtpField', () {
    testWidgets('fills boxes, drops non-digits, completes at 6', (
      tester,
    ) async {
      String? done;
      await tester.pumpWidget(
        kHarness(KOtpField(onCompleted: (v) => done = v)),
      );
      await tester.enterText(find.byType(TextField), '48a2');
      await tester.pump();
      expect(find.text('4'), findsOneWidget);
      expect(find.text('a'), findsNothing);
      expect(done, isNull);
      // Pasting the whole code also works.
      await tester.enterText(find.byType(TextField), '482913');
      expect(done, '482913');
    });
  });

  group('KQtyStepper', () {
    testWidgets('respects min and max', (tester) async {
      var value = 1;
      await tester.pumpWidget(
        kHarness(
          StatefulBuilder(
            builder: (context, setState) => KQtyStepper(
              value: value,
              max: 2,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Decrease'));
      expect(value, 1);
      await tester.tap(find.bySemanticsLabel('Increase'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Increase'));
      await tester.pump();
      expect(value, 2);
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('KProductCard', () {
    testWidgets('retail shows price and KHR', (tester) async {
      await tester.pumpWidget(
        kHarness(
          const SizedBox(
            width: 180,
            child: KProductCard(
              name: 'Headphones',
              image: KProductArt(icon: KIcons.headphones),
              price: r'$49.00',
              khrAmount: '200,900',
              wishlisted: false,
              onWishlist: _noop,
            ),
          ),
        ),
      );
      expect(find.text(r'$49.00'), findsOneWidget);
      expect(find.text('≈ KHR 200,900'), findsOneWidget);
      expect(find.bySemanticsLabel('Add to wishlist'), findsOneWidget);
    });

    testWidgets('business never shows a price', (tester) async {
      await tester.pumpWidget(
        kHarness(
          const SizedBox(
            width: 180,
            child: KProductCard.business(
              name: 'A4 paper',
              image: KProductArt(icon: KIcons.paper),
              minQuantity: '20 reams',
            ),
          ),
        ),
      );
      expect(find.text('Price on quote'), findsOneWidget);
      expect(find.text('Min. 20 reams'), findsOneWidget);
      expect(find.textContaining(r'$'), findsNothing);
      expect(find.textContaining('KHR'), findsNothing);
    });
  });

  group('KStatusPill', () {
    testWidgets('renders localized labels', (tester) async {
      await tester.pumpWidget(
        kHarness(
          Wrap(
            children: [
              KStatusPill.order(OrderStatus.outForDelivery),
              KStatusPill.payment(PaymentStatus.paid),
              KStatusPill.quote(QuoteStatus.quoteReady),
            ],
          ),
        ),
      );
      expect(find.text('Out for delivery'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Quote ready'), findsOneWidget);
    });

    testWidgets('renders in Khmer', (tester) async {
      await tester.pumpWidget(
        kHarness(
          KStatusPill.order(OrderStatus.delivered),
          locale: const Locale('km'),
        ),
      );
      expect(find.text('បានដឹកដល់'), findsOneWidget);
    });
  });

  group('KBottomNav', () {
    Future<void> pump(
      WidgetTester tester,
      KBottomNav Function(BuildContext) nav,
    ) => tester.pumpWidget(kHarness(Builder(builder: nav)));

    void none(int _) {}

    final layouts = <String, (KBottomNav Function(BuildContext), List<String>)>{
      'customer': (
        (c) => KBottomNav.customer(c, currentIndex: 0, onTap: none),
        ['Home', 'Categories', 'Cart', 'Orders', 'Account'],
      ),
      'guest': (
        (c) => KBottomNav.guest(c, currentIndex: 0, onTap: none),
        ['Home', 'Categories', 'Cart', 'Account'],
      ),
      'business': (
        (c) => KBottomNav.business(c, currentIndex: 0, onTap: none),
        ['Home', 'Categories', 'Quote list', 'Orders and quotes', 'Account'],
      ),
      'rider': (
        (c) => KBottomNav.rider(c, currentIndex: 0, onTap: none),
        ['Jobs', 'History', 'Cash', 'Account'],
      ),
      'admin': (
        (c) => KBottomNav.admin(c, currentIndex: 0, onTap: none),
        ['Dashboard', 'Orders', 'RFQs', 'Chat', 'More'],
      ),
    };

    for (final MapEntry(key: role, value: (build, labels)) in layouts.entries) {
      testWidgets('$role layout matches the board', (tester) async {
        await pump(tester, build);
        final nav = tester.widget<KBottomNav>(find.byType(KBottomNav));
        expect(nav.items.map((i) => i.label.replaceAll('&', 'and')), labels);
      });
    }

    testWidgets('badge is in the label and taps report the index', (
      tester,
    ) async {
      int? tapped;
      await pump(
        tester,
        (c) => KBottomNav.customer(
          c,
          currentIndex: 0,
          cartCount: 3,
          onTap: (i) => tapped = i,
        ),
      );
      expect(find.text('3'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Cart, 3 new'));
      expect(tapped, 2);
    });
  });

  group('overlays', () {
    Future<BuildContext> pumpHost(WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        kHarness(
          Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      return ctx;
    }

    testWidgets('confirm resolves true on confirm, false on cancel', (
      tester,
    ) async {
      final ctx = await pumpHost(tester);
      Future<bool> open() => showKConfirm(
        ctx,
        tone: KConfirmTone.destructive,
        title: 'Remove from cart?',
        message: 'It will be removed.',
        cancelLabel: 'Keep it',
        confirmLabel: 'Remove',
      );
      var result = open();
      await tester.pumpAndSettle();
      expect(find.text('Remove from cart?'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);

      result = open();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });

    testWidgets('bottom sheet closes from its close button', (tester) async {
      final ctx = await pumpHost(tester);
      final sheet = showKBottomSheet<void>(
        ctx,
        title: 'Sort by',
        builder: (_) => const Text('Newest'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Newest'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      await sheet;
      expect(find.text('Newest'), findsNothing);
    });

    testWidgets('toast runs its action and hides after 4 s', (tester) async {
      final ctx = await pumpHost(tester);
      var undone = false;
      showKToast(
        ctx,
        message: 'Item removed',
        actionLabel: 'Undo',
        onAction: () => undone = true,
      );
      await tester.pump();
      expect(find.text('Item removed'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(undone, isTrue);
      expect(find.text('Item removed'), findsNothing);

      showKToast(ctx, message: 'Added to cart');
      await tester.pump();
      expect(find.text('Added to cart'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Added to cart'), findsNothing);
    });
  });

  testWidgets('KAppBar shows back only when asked or poppable', (tester) async {
    await tester.pumpWidget(
      kHarness(
        const Column(
          children: [
            KAppBar(title: 'Checkout'),
            KAppBar(title: 'Cart', showBack: true),
          ],
        ),
      ),
    );
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
  });
}

void _noop() {}
