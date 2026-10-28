import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:k_e_commerce/core/l10n/generated/app_localizations_en.dart';
import 'package:k_e_commerce/features/admin/domain/staff_permissions.dart';
import 'package:k_e_commerce/features/admin/domain/staff_role.dart';
import 'package:k_e_commerce/features/catalog/data/catalog_repository.dart';
import 'package:k_e_commerce/features/catalog/data/product_read_repository.dart';
import 'package:k_e_commerce/features/catalog/domain/catalog_list.dart';
import 'package:k_e_commerce/features/catalog/domain/catalog_outcome.dart';
import 'package:k_e_commerce/features/catalog/domain/csv_import.dart';
import 'package:k_e_commerce/features/catalog/domain/i18n_text.dart';
import 'package:k_e_commerce/features/catalog/domain/product_draft.dart';
import 'package:k_e_commerce/features/catalog/presentation/catalog_labels.dart';

import 'fakes.dart';

void main() {
  final l10n = AppLocalizationsEn();

  group('I18nText', () {
    test('flags a missing Khmer translation and falls back to English', () {
      const text = I18nText(en: 'Mug');
      expect(text.missingKm, isTrue);
      expect(text.of('km'), 'Mug');
      expect(const I18nText(en: 'Mug', km: 'កែវ').of('km'), 'កែវ');
      expect(const I18nText().missingKm, isFalse);
    });

    test('reads jsonb and writes only filled, trimmed locales', () {
      expect(I18nText.fromJson({'en': 'A'}), const I18nText(en: 'A'));
      expect(I18nText.fromJson(null), const I18nText());
      expect(const I18nText(en: ' A ', km: ' ').toJson(), {'en': 'A'});
    });
  });

  group('ProductDraft', () {
    test(
      'the saved headphones are valid and the payload matches catalog-manage',
      () {
        expect(headphones.validate(), isEmpty);
        final payload = headphones.toPayload();
        expect(payload['id'], 'p-hp');
        expect(payload['status'], 'active');
        expect(payload['rfq_min_qty'], 5);
        expect((payload['variants'] as List).first, {
          'id': 'v-blk',
          'sku': 'HP-PRO-BLK',
          'attributes': {'Colour': 'Black'},
          'active': true,
          'price_cents': 4900,
        });
        expect((payload['images'] as List).single, {
          'id': 'i-1',
          'path': 'products/p-hp/front.jpg',
          'alt': {'en': 'Black headphones, front'},
          'variant_sku': 'HP-PRO-BLK',
        });
      },
    );

    test('opening stock is sent for new variants only', () {
      const fresh = VariantDraft(sku: 'A-1', priceCents: 100, initialQty: 5);
      expect(fresh.toJson()['initial_qty'], 5);
      final saved = headphones.variants.first.copyWith(initialQty: () => 5);
      expect(saved.toJson().containsKey('initial_qty'), isFalse);
    });

    test('lists every problem with the same field paths as the server', () {
      const draft = ProductDraft(
        variants: [
          VariantDraft(sku: 'bad sku', priceCents: 0),
          VariantDraft(sku: 'OK-1'),
          VariantDraft(sku: 'ok-1', priceCents: 100, initialQty: -1),
        ],
        rfqEnabled: true,
        images: [
          ImageDraft(
            path: 'products/x/1.jpg',
            url: 'u',
            alt: I18nText(km: 'x'),
          ),
        ],
      );
      expect(draft.validate(), [
        const FieldIssue('name.en', IssueCode.required),
        const FieldIssue('category_id', IssueCode.required),
        const FieldIssue('variants.0.sku', IssueCode.invalid),
        const FieldIssue('variants.0.price_cents', IssueCode.invalid),
        const FieldIssue('variants.1.price_cents', IssueCode.required),
        const FieldIssue('variants.2.sku', IssueCode.duplicate),
        const FieldIssue('variants.2.initial_qty', IssueCode.invalid),
        const FieldIssue('rfq_min_qty', IssueCode.required),
        const FieldIssue('images.0.alt', IssueCode.required),
      ]);
    });

    test('issues point at the tab that shows them', () {
      expect(
        const FieldIssue('name.km', IssueCode.tooLong).tab,
        ProductTab.general,
      );
      expect(
        const FieldIssue('rfq_min_qty', IssueCode.required).tab,
        ProductTab.variants,
      );
      expect(
        const FieldIssue('images.2.alt', IssueCode.required).tab,
        ProductTab.images,
      );
    });

    test('notices unsaved changes', () {
      expect(headphones.sameContentAs(headphones), isTrue);
      final renamed = headphones.copyWith(
        name: headphones.name.copyWith(km: 'កាស'),
      );
      expect(renamed.sameContentAs(headphones), isFalse);
      final reordered = headphones.copyWith(
        images: [...headphones.images.reversed],
      );
      expect(reordered.sameContentAs(headphones), isTrue);
    });
  });

  group('variantsForOptions', () {
    test('builds every combination with SKUs from the prefix', () {
      final variants = variantsForOptions(
        const [
          ProductOption(
            name: I18nText(en: 'Colour'),
            values: ['Black', 'White'],
          ),
          ProductOption(
            name: I18nText(en: 'Size'),
            values: ['M', 'L'],
          ),
        ],
        const [VariantDraft(priceCents: 990)],
        skuPrefix: 'tsh',
      );
      expect(variants.map((v) => v.sku), [
        'TSH-BLC-M',
        'TSH-BLC-L',
        'TSH-WHT-M',
        'TSH-WHT-L',
      ]);
      expect(variants.map((v) => v.label()), [
        'Black / M',
        'Black / L',
        'White / M',
        'White / L',
      ]);
      expect(variants.every((v) => v.priceCents == 990), isTrue);
    });

    test('keeps saved variants and stops selling ones no longer offered', () {
      final variants = variantsForOptions(
        const [
          ProductOption(
            name: I18nText(en: 'Colour'),
            values: ['Black', 'Red'],
          ),
        ],
        headphones.variants,
        skuPrefix: 'HP-PRO',
      );
      expect(variants.map((v) => (v.sku, v.active, v.isNew)), [
        ('HP-PRO-BLK', true, false),
        ('HP-PRO-RD', true, true),
        ('HP-PRO-WHT', false, false),
        ('HP-PRO-SKY', false, false),
      ]);
    });

    test('without usable options the variants stay as they are', () {
      expect(
        variantsForOptions(const [ProductOption()], headphones.variants),
        same(headphones.variants),
      );
    });
  });

  group('CSV head and column matching', () {
    test('parses quoted fields, counts rows and empty cells', () {
      final head = CsvHead.parse(
        '﻿name,name_km,price_usd,notes\r\n'
        '"Mug, set of 4",,"1,250.50","He said ""hi""\nthen left"\r\n'
        'Kettle,កំសៀវ,12,\r\n'
        '\r\n',
      )!;
      expect(head.header, ['name', 'name_km', 'price_usd', 'notes']);
      expect(head.sample, [
        'Mug, set of 4',
        '',
        '1,250.50',
        'He said "hi"\nthen left',
      ]);
      expect(head.rowCount, 2);
      expect(head.emptyCounts, [0, 1, 0, 1]);
      expect(CsvHead.parse(''), isNull);
    });

    test('matches the template and common names; the rest is not imported', () {
      final mapping = autoMapping([
        'name',
        'name_km',
        'SKU',
        'Price USD',
        'qty',
        'category',
        'supplier_code',
        'Name',
      ]);
      expect(mapping, {
        'name': ImportField.nameEn,
        'name_km': ImportField.nameKm,
        'SKU': ImportField.sku,
        'Price USD': ImportField.priceUsd,
        'qty': ImportField.qty,
        'category': ImportField.category,
        'supplier_code': ImportField.ignore,
        'Name': ImportField.ignore,
      });
      expect(missingFields(mapping), isEmpty);
      expect(missingFields({'a': ImportField.sku}), [
        ImportField.nameEn,
        ImportField.priceUsd,
        ImportField.category,
      ]);
    });

    test('reads catalog-import answers', () {
      final preview = ImportOutcome.fromJson({
        'status': 'preview',
        'rows': 120,
        'valid': 117,
        'products': 90,
        'errors': [
          {'row': 37, 'code': 'sku_exists', 'value': 'MUG-4-SND'},
        ],
      });
      expect(preview, isA<ImportPreview>());
      final error = (preview as ImportPreview).errors.single;
      expect(
        importRowMessage(l10n, error),
        'Row 37: SKU "MUG-4-SND" already exists',
      );
      expect(
        ImportOutcome.fromJson({'status': 'too_large'}),
        isA<ImportRefused>().having(
          (r) => r.reason,
          'reason',
          ImportRefusal.tooLarge,
        ),
      );
    });
  });

  group('catalog-manage answers', () {
    test('become outcomes', () {
      expect(
        CatalogOutcome.fromJson({'status': 'saved', 'id': 'p-1'}),
        isA<CatalogSaved>().having((s) => s.id, 'id', 'p-1'),
      );
      final invalid = CatalogOutcome.fromJson({
        'status': 'invalid',
        'errors': [
          {'field': 'variants.0.sku', 'code': 'duplicate'},
        ],
      });
      expect(
        (invalid as CatalogInvalid).issues.single,
        const FieldIssue('variants.0.sku', IssueCode.duplicate),
      );
      expect(
        outcomeMessage(
          l10n,
          CatalogOutcome.fromJson({'status': 'sku_taken', 'sku': 'A'}),
        ),
        'SKU A is already used by another product.',
      );
      expect(
        CatalogOutcome.fromJson({'status': 'forbidden'}),
        isA<CatalogRefused>().having(
          (r) => r.reason,
          'reason',
          CatalogRefusal.forbidden,
        ),
      );
    });
  });

  group('labels', () {
    test('stock pills as on A-05', () {
      String pill(CatalogListItem item) => stockPill(l10n, item).$1;
      expect(pill(listItem('a', 'A', available: 52)), '52');
      expect(
        pill(
          listItem('a', 'A', stock: StockState.low, available: 52, outCount: 1),
        ),
        '52 · 1 out',
      );
      expect(
        pill(listItem('a', 'A', stock: StockState.low, available: 4)),
        '4 · low',
      );
      expect(pill(listItem('a', 'A', stock: StockState.out)), 'Out of stock');
      expect(pill(listItem('a', 'A', stock: StockState.none)), 'Not stocked');
    });

    test('prices typed in the editor', () {
      expect(parseUsdCents('49'), 4900);
      expect(parseUsdCents(r'$1,249.5'), 124950);
      expect(parseUsdCents('49.'), 4900);
      expect(parseUsdCents('4.999'), isNull);
      expect(parseUsdCents('abc'), isNull);
      expect(centsInput(4950), '49.50');
      expect(priceRange(l10n, 990, 1250), r'$9.90 – $12.50');
      expect(priceRange(l10n, 990, 990), r'$9.90');
    });

    test('field messages', () {
      expect(
        issueMessage(l10n, const FieldIssue('name.en', IssueCode.required)),
        'Enter the English name.',
      );
      expect(
        issueMessage(
          l10n,
          const FieldIssue('variants.1.sku', IssueCode.invalid),
        ),
        'Use letters, numbers, dot, dash or underscore.',
      );
      expect(
        issueMessage(
          l10n,
          const FieldIssue('images.0.alt', IssueCode.required),
        ),
        'Add a short description',
      );
    });
  });

  group('permissions', () {
    test('only super admins and catalog staff edit products', () {
      expect(canEdit(StaffRole.superAdmin, PermissionArea.products), isTrue);
      expect(canEdit(StaffRole.catalog, PermissionArea.products), isTrue);
      expect(canEdit(StaffRole.sales, PermissionArea.products), isFalse);
      expect(canEdit(StaffRole.support, PermissionArea.products), isFalse);
    });
  });

  group('rows from Supabase', () {
    test('a product row becomes the editor draft', () {
      final draft = productDraftFromRow({
        'id': 'p-1',
        'category_id': 'c-audio',
        'slug': 'speaker',
        'brand': 'Sonora',
        'name': {'en': 'Speaker'},
        'description': {},
        'highlights': [
          {'en': '12-hour battery'},
        ],
        'specs': {'model': 'SPK-1'},
        'tags': ['New'],
        'options': [
          {
            'name': {'en': 'Colour'},
            'values': ['Black'],
          },
        ],
        'status': 'active',
        'rfq_enabled': false,
        'rfq_multiple': 1,
        'created_at': '2026-10-20T03:00:00Z',
        'creator': {'full_name': 'Visal Keo'},
        'editor': null,
        'product_variants': [
          {
            'id': 'v-2',
            'sku': 'SPK-SKY',
            'attributes': {'Colour': 'Sky'},
            'sort': 2,
            'active': false,
            'prices': {'amount_cents': 2900, 'compare_at_cents': null},
            'stock': <Object>[],
          },
          {
            'id': 'v-1',
            'sku': 'SPK-BLK',
            'attributes': {'Colour': 'Black'},
            'sort': 1,
            'active': true,
            'prices': {'amount_cents': 2900, 'compare_at_cents': null},
            'stock': [
              {'qty': 12, 'reserved': 2, 'low_stock_at': 10},
            ],
          },
        ],
        'product_images': [
          {
            'id': 'i-2',
            'path': 'products/p-1/b.jpg',
            'alt': {'en': 'Back'},
            'sort': 1,
            'variant_id': null,
          },
          {
            'id': 'i-1',
            'path': 'products/p-1/a.jpg',
            'alt': {'en': 'Front'},
            'sort': 0,
            'variant_id': 'v-1',
          },
        ],
      }, imageUrl: (p) => 'https://cdn/$p');
      expect(draft.specs, [const Spec(name: 'model', value: 'SPK-1')]);
      expect(draft.variants.map((v) => v.sku), ['SPK-BLK', 'SPK-SKY']);
      expect(draft.variants.first.available, 10);
      expect(draft.variants.first.stocked, isTrue);
      expect(draft.variants.last.active, isFalse);
      expect(draft.mainImage!.url, 'https://cdn/products/p-1/a.jpg');
      expect(draft.mainImage!.variantSku, 'SPK-BLK');
      expect(draft.summary.createdBy, 'Visal Keo');
      expect(draft.validate(), isEmpty);
    });

    test(
      'customers get prices, images in order and stock; business buyers no price',
      () {
        Map<String, dynamic> row({required bool withPrice}) => {
          'id': 'p-1',
          'slug': 'speaker',
          'name': {'en': 'Speaker'},
          'rfq_enabled': true,
          'rfq_min_qty': 10,
          'product_images': [
            {
              'path': 'b.jpg',
              'alt': {'en': 'Back'},
              'sort': 1,
            },
            {
              'path': 'a.jpg',
              'alt': {'en': 'Front'},
              'sort': 0,
            },
          ],
          'product_variants': [
            {
              'id': 'v-1',
              'sku': 'SPK-BLK',
              'sort': 1,
              'active': true,
              'attributes': {'Colour': 'Black'},
              'prices': withPrice ? {'amount_cents': 2900} : null,
            },
            {
              'id': 'v-2',
              'sku': 'SPK-SKY',
              'sort': 2,
              'active': true,
              'attributes': {'Colour': 'Sky'},
              'prices': withPrice ? {'amount_cents': 2500} : null,
            },
          ],
        };
        final shopper = productViewFromRow(
          row(withPrice: true),
          imageUrl: (p) => 'https://cdn/$p',
          availability: {'v-1': 3},
        );
        expect(shopper.mainImageUrl, 'https://cdn/a.jpg');
        expect(shopper.imageAlts.first.en, 'Front');
        expect(shopper.fromPriceCents, 2500);
        expect(shopper.soldOut, isFalse);
        expect(shopper.rfqMinQty, 10);

        final business = productViewFromRow(
          row(withPrice: false),
          imageUrl: (p) => p,
        );
        expect(business.fromPriceCents, isNull);
        expect(business.soldOut, isTrue);
      },
    );

    test('photo paths stay inside the product folder', () {
      final path = productImagePath('p-1', 'Front Shot.JPEG', _FixedRandom());
      expect(path, 'products/p-1/0000000000000000.jpg');
      expect(imageContentType('a.webp'), 'image/webp');
      expect(imageContentType('a.gif'), isNull);
    });

    test('categories in tree order with their paths', () {
      final tree = categoryTree(seedCategories, 'en');
      expect(tree.map((e) => (e.path, e.depth)), [
        ('Electronics', 0),
        ('Electronics › Audio', 1),
        ('Kitchen', 0),
      ]);
    });
  });
}

class _FixedRandom implements Random {
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}
