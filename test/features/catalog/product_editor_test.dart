import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:k_e_commerce/core/router/app_router.dart';
import 'package:k_e_commerce/core/router/app_routes.dart';
import 'package:k_e_commerce/core/ui/k_ui.dart';
import 'package:k_e_commerce/features/catalog/domain/catalog_outcome.dart';
import 'package:k_e_commerce/features/catalog/domain/i18n_text.dart';
import 'package:k_e_commerce/features/catalog/domain/product_draft.dart';
import 'package:k_e_commerce/features/catalog/presentation/archive_dialog.dart';
import 'package:k_e_commerce/features/catalog/presentation/catalog_list_page.dart';
import 'package:k_e_commerce/features/catalog/presentation/product_editor_page.dart';

import '../admin/admin_harness.dart';
import '../auth/auth_harness.dart' show settleToasts;
import 'fakes.dart';

class _Opened {
  _Opened(this.repo, this.picker, this.router);
  final FakeCatalogRepository repo;
  final FakeFilePicker picker;
  final String Function() router;
}

Future<_Opened> _open(
  WidgetTester tester, {
  String location = '/admin/catalog/p-hp',
  String email = 'visal@kstore.example',
  Size size = desktop,
}) async {
  final repo = FakeCatalogRepository();
  final picker = FakeFilePicker();
  final container = await pumpAdmin(
    tester,
    email: email,
    size: size,
    location: location,
    overrides: catalogOverrides(repo, picker: picker),
  );
  return _Opened(
    repo,
    picker,
    () => container
        .read(routerProvider)
        .routerDelegate
        .currentConfiguration
        .uri
        .path,
  );
}

/// The text input of the [index]th field labelled (or hinted) [label].
Finder _field(String label, [int index = 0]) => find
    .descendant(
      of: find.byWidgetPredicate(
        (w) => w is KTextField && (w.label == label || w.hint == label),
      ),
      matching: find.byType(TextField),
    )
    .at(index);

Future<void> _type(WidgetTester tester, Finder field, String text) async {
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Finder _button(String label) => find.widgetWithText(KButton, label);

/// Scrolls the page back to its header (title, actions, tabs).
Future<void> _top(WidgetTester tester) async {
  final page = find.descendant(
    of: find.byType(ProductEditor),
    matching: find.byType(Scrollable),
  );
  tester.state<ScrollableState>(page.first).position.jumpTo(0);
  await tester.pumpAndSettle();
}

/// Taps a header button (scrolling up to it first).
Future<void> _press(WidgetTester tester, String label) async {
  await _top(tester);
  await _tap(tester, _button(label));
}

void main() {
  setUpAll(initializeDateFormatting);

  group('A-05a General', () {
    testWidgets('shows the product with missing-translation flags', (
      tester,
    ) async {
      await _open(tester);
      expect(find.text('Wireless Headphones Pro'), findsWidgets);
      expect(find.text('HP-PRO-BLK · 3 variants · Audio'), findsOneWidget);
      // Khmer name and description are both missing.
      expect(find.text('Translation missing'), findsNWidgets(2));
      expect(find.text('Wireless'), findsOneWidget);
      expect(find.text('2 Sep · Visal Keo'), findsOneWidget);
      expect(find.text('4.6 · 128 reviews'), findsOneWidget);
      // Nothing changed yet, so nothing to save.
      expect(tester.widget<KButton>(_button('Save changes')).onPressed, isNull);

      await _type(tester, _field('Name (Khmer)'), 'កាសឥតខ្សែ');
      expect(find.text('Translation missing'), findsOneWidget);
      await _top(tester);
      expect(
        tester.widget<KButton>(_button('Save changes')).onPressed,
        isNotNull,
      );
    });

    testWidgets('saves highlights, specs and tags', (tester) async {
      final opened = await _open(tester);
      await _tap(tester, _button('Add highlight'));
      await _type(
        tester,
        find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is KTextField && w.hint == 'Highlight (English)',
          ),
          matching: find.byType(TextField),
        ),
        '30-hour battery',
      );
      await _tap(tester, _button('Add row'));
      final specName = find.descendant(
        of: find.byWidgetPredicate((w) => w is KTextField && w.hint == 'Name'),
        matching: find.byType(TextField),
      );
      final specValue = find.descendant(
        of: find.byWidgetPredicate((w) => w is KTextField && w.hint == 'Value'),
        matching: find.byType(TextField),
      );
      await _type(tester, specName, 'Battery');
      await _type(tester, specValue, '30 h');
      final tag = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is KTextField && w.hint == 'Type a tag and press Enter',
        ),
        matching: find.byType(TextField),
      );
      await _type(tester, tag, 'Noise cancelling');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Noise cancelling'), findsOneWidget);

      await _press(tester, 'Save changes');
      final saved = opened.repo.saved.single;
      expect(saved.highlights, [const I18nText(en: '30-hour battery')]);
      expect(saved.specs, [const Spec(name: 'Battery', value: '30 h')]);
      expect(saved.tags, ['Wireless', 'Noise cancelling']);
      expect(find.text('Product saved.'), findsOneWidget);
      await settleToasts(tester);
    });

    testWidgets('a new product must have a name, category and price', (
      tester,
    ) async {
      final opened = await _open(tester, location: AppRoutes.adminProductNew);
      expect(find.text('New product'), findsWidgets);
      await _press(tester, 'Create product');
      expect(opened.repo.saved, isEmpty);
      expect(find.text('Check the highlighted fields.'), findsOneWidget);
      expect(find.text('Enter the English name.'), findsOneWidget);
      expect(find.text('Choose a category.'), findsOneWidget);
      await settleToasts(tester);

      await _type(tester, _field('Name (English)'), 'Studio Monitor');
      expect(find.text('Enter the English name.'), findsNothing);
      await _tap(tester, _field('Category'));
      await _tap(tester, find.text('Audio').last);
      expect(find.text('Electronics › Audio'), findsOneWidget);

      await _top(tester);
      await _tap(tester, find.text('Variants & pricing'));
      await _type(tester, _field('SKU'), 'MON-1');
      await _type(tester, _field('Price (USD)'), '129');
      // KHR preview at 4,100 riel per dollar.
      expect(find.text('528,900'), findsOneWidget);
      await _type(tester, _field('Opening stock'), '8');

      await _press(tester, 'Create product');
      final saved = opened.repo.saved.single;
      expect(saved.name, const I18nText(en: 'Studio Monitor'));
      expect(saved.categoryId, 'c-audio');
      expect(saved.variants.single.priceCents, 12900);
      expect(saved.toPayload()['variants'], [
        {
          'sku': 'MON-1',
          'attributes': <String, String>{},
          'active': true,
          'price_cents': 12900,
          'initial_qty': 8,
        },
      ]);
      expect(find.text('Product created.'), findsOneWidget);
      expect(opened.router(), '/admin/catalog/p-new');
      await settleToasts(tester);
    });

    testWidgets('leaving with unsaved changes asks first', (tester) async {
      final opened = await _open(tester);
      await _type(tester, _field('Brand'), 'Sonora Audio');
      await _press(tester, 'Products');
      expect(find.text('Leave without saving?'), findsOneWidget);
      await _tap(tester, find.text('Keep editing'));
      expect(opened.router(), '/admin/catalog/p-hp');

      await _press(tester, 'Products');
      await _tap(tester, find.text('Leave'));
      expect(opened.router(), '/admin/catalog');
      expect(find.byType(CatalogListPage), findsOneWidget);
    });
  });

  group('A-05b Variants & pricing', () {
    testWidgets('shows the KHR preview, stock and price history', (
      tester,
    ) async {
      await _open(tester);
      await _top(tester);
      await _tap(tester, find.text('Variants & pricing'));
      expect(find.text('200,900'), findsNWidgets(3));
      expect(
        find.text(
          "KHR prices use today's rate of 4,100 · change it in Settings › Payments.",
        ),
        findsOneWidget,
      );
      expect(find.text('Low'), findsOneWidget); // 11 left, alert at 15
      expect(find.text('Out'), findsOneWidget);
      expect(find.text('11 · alert at 15'), findsOneWidget);
      expect(find.text(r'HP-PRO-BLK: $52.00 → $49.00'), findsOneWidget);
      expect(find.text('Quote enabled'), findsOneWidget);
    });

    testWidgets('a price change is confirmed before saving', (tester) async {
      final opened = await _open(tester);
      await _top(tester);
      await _tap(tester, find.text('Variants & pricing'));
      await _type(tester, _field('Price (USD)'), '52.00');
      expect(find.text('213,200'), findsOneWidget);

      await _press(tester, 'Save changes');
      expect(find.text('Change prices?'), findsOneWidget);
      expect(
        find.textContaining('1 variant gets a new price.'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Cancel'));
      expect(opened.repo.saved, isEmpty);

      await _press(tester, 'Save changes');
      await _tap(tester, find.text('Save new prices'));
      expect(opened.repo.saved.single.variants.first.priceCents, 5200);
      await settleToasts(tester);
    });

    testWidgets('options build the variants', (tester) async {
      final opened = await _open(tester);
      await _top(tester);
      await _tap(tester, find.text('Variants & pricing'));
      final value = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is KTextField && w.hint == 'Type a value and press Enter',
        ),
        matching: find.byType(TextField),
      );
      await _type(tester, value, 'Red');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Red'), findsWidgets);
      await _type(tester, _field('Opening stock'), '5');

      await _press(tester, 'Save changes');
      final variants = opened.repo.saved.single.variants;
      expect(variants.map((v) => v.sku), [
        'HP-PRO-BLK',
        'HP-PRO-WHT',
        'HP-PRO-SKY',
        'HP-PRO-RD',
      ]);
      expect(variants.last.priceCents, 4900);
      expect(variants.last.initialQty, 5);
      await settleToasts(tester);
    });

    testWidgets('quotes need a minimum quantity', (tester) async {
      final opened = await _open(tester);
      await _top(tester);
      await _tap(tester, find.text('Variants & pricing'));
      await _type(tester, _field('Minimum quote quantity'), '');
      await _press(tester, 'Save changes');
      expect(
        find.text('Enter the minimum quantity for quotes.'),
        findsOneWidget,
      );
      expect(opened.repo.saved, isEmpty);
      await settleToasts(tester);
    });

    testWidgets('a SKU used elsewhere is shown on its field', (tester) async {
      final opened = await _open(tester);
      opened.repo.next = const CatalogSkuTaken('HP-PRO-WHT');
      await _type(tester, _field('Brand'), 'Sonora Audio');
      await _press(tester, 'Save changes');
      expect(
        find.text('SKU HP-PRO-WHT is already used by another product.'),
        findsOneWidget,
      );
      expect(find.text('Used twice.'), findsOneWidget);
      await settleToasts(tester);
    });
  });

  group('A-05c Images', () {
    testWidgets(
      'uploads photos, needs a description, reorders the main image',
      (tester) async {
        final opened = await _open(tester);
        await _top(tester);
        await _tap(tester, find.text('Images'));
        expect(find.text('Main image'), findsOneWidget);

        opened.picker.next = [
          (name: 'side.png', bytes: Uint8List(10)),
          (name: 'clip.gif', bytes: Uint8List(10)),
          (name: 'huge.jpg', bytes: Uint8List(CatalogLimits.imageBytes + 1)),
        ];
        await _tap(tester, _button('Add images'));
        expect(opened.picker.asked.single, ['jpg', 'jpeg', 'png', 'webp']);
        expect(opened.repo.calls, ['upload p-hp side.png']);
        expect(
          find.text('1 image has no description. Add it before saving.'),
          findsOneWidget,
        );
        await settleToasts(tester);

        await _press(tester, 'Save changes');
        expect(find.text('Add a short description'), findsOneWidget);
        expect(opened.repo.saved, isEmpty);
        await settleToasts(tester);

        await _type(tester, _field('Image 2'), 'Headphones, side');
        await _tap(tester, _button('Set as main'));
        await _press(tester, 'Save changes');
        final images = opened.repo.saved.single.images;
        expect(images.map((i) => i.alt.en), [
          'Headphones, side',
          'Black headphones, front',
        ]);
        expect(images.first.path, 'products/p-hp/0.jpg');
        await settleToasts(tester);
      },
    );

    testWidgets('deleting a photo asks first', (tester) async {
      final opened = await _open(tester);
      await _top(tester);
      await _tap(tester, find.text('Images'));
      await _tap(tester, find.bySemanticsLabel('Delete image'));
      expect(find.text('Delete this image?'), findsOneWidget);
      await _tap(tester, find.text('Delete image').last);
      expect(find.text('No images yet'), findsOneWidget);
      await _press(tester, 'Save changes');
      expect(opened.repo.saved.single.images, isEmpty);
      await settleToasts(tester);
    });
  });

  group('A-05e archive and restore', () {
    testWidgets('archive shows what it touches and asks first', (tester) async {
      final opened = await _open(tester);
      await _press(tester, 'Archive');
      expect(find.byType(ArchiveDialog), findsOneWidget);
      expect(find.text('Archive Wireless Headphones Pro?'), findsWidgets);
      expect(find.text('3 · 52 in stock'), findsOneWidget);
      expect(find.text('2 (will still ship)'), findsOneWidget);
      await _tap(tester, find.text('Cancel'));
      expect(opened.repo.calls, isEmpty);

      await _press(tester, 'Archive');
      await _tap(tester, find.text('Archive product'));
      expect(opened.repo.calls, ['archive p-hp']);
      expect(find.text('Wireless Headphones Pro archived.'), findsOneWidget);
      expect(opened.router(), '/admin/catalog');
      await settleToasts(tester);
    });

    testWidgets('an archived product can be restored as a draft', (
      tester,
    ) async {
      final repo = FakeCatalogRepository(
        products: {
          'p-old': const ProductDraft(
            id: 'p-old',
            categoryId: 'c-audio',
            name: I18nText(en: 'Old Speaker'),
            status: ProductStatus.archived,
            variants: [
              VariantDraft(id: 'v-1', sku: 'OLD-1', priceCents: 1000),
            ],
          ),
        },
      );
      await pumpAdmin(
        tester,
        email: 'chenda@kstore.example',
        location: '/admin/catalog/p-old',
        overrides: catalogOverrides(repo),
      );
      expect(_button('Archive'), findsNothing);
      await _press(tester, 'Restore');
      expect(repo.calls, ['restore p-old']);
      expect(find.text('Old Speaker restored as a draft.'), findsOneWidget);
      await settleToasts(tester);
    });
  });

  group('Preview and read-only', () {
    testWidgets(
      'Preview shows the product as shoppers and business buyers see it',
      (tester) async {
        await _open(tester);
        await _press(tester, 'Preview');
        expect(find.text('Customer preview'), findsOneWidget);
        expect(find.text('Shoppers see'), findsOneWidget);
        expect(find.text(r'$49.00'), findsOneWidget);
        expect(find.text('Business buyers see'), findsOneWidget);
        expect(find.text('Min. 5 pieces'), findsOneWidget);
      },
    );

    testWidgets('sales and support only look', (tester) async {
      await _open(tester, email: 'sophea@kstore.example');
      expect(_button('Save changes'), findsNothing);
      expect(_button('Archive'), findsNothing);
      expect(_button('Preview'), findsOneWidget);
      expect(
        tester.widget<TextField>(_field('Name (English)')).readOnly,
        isTrue,
      );
    });

    testWidgets('read-only roles cannot open new or import', (tester) async {
      final opened = await _open(
        tester,
        email: 'dalin@kstore.example',
        location: AppRoutes.adminProductNew,
      );
      expect(opened.router(), '/admin/catalog');
    });

    testWidgets('works on a phone', (tester) async {
      await _open(tester, size: phone);
      expect(find.text('Wireless Headphones Pro'), findsWidgets);
      await _top(tester);
      await _tap(tester, find.text('Variants & pricing'));
      expect(find.text('200,900'), findsNWidgets(3));
    });

    testWidgets('a missing product says so', (tester) async {
      await _open(tester, location: '/admin/catalog/p-none');
      expect(find.text('This product no longer exists.'), findsOneWidget);
    });
  });
}
