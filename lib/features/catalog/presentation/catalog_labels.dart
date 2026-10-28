import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/money_format.dart';
import '../../../core/ui/k_ui.dart';
import '../domain/catalog_list.dart';
import '../domain/catalog_outcome.dart';
import '../domain/csv_import.dart';
import '../domain/product_draft.dart';

String statusLabel(AppLocalizations l10n, ProductStatus status) =>
    switch (status) {
      ProductStatus.active => l10n.catalogStatusActive,
      ProductStatus.draft => l10n.catalogStatusDraft,
      ProductStatus.archived => l10n.catalogStatusArchived,
    };

KTone statusTone(ProductStatus status) => switch (status) {
  ProductStatus.active => KTone.green,
  ProductStatus.draft => KTone.gray,
  ProductStatus.archived => KTone.amber,
};

String tabLabel(AppLocalizations l10n, CatalogTab tab) => switch (tab) {
  CatalogTab.all => l10n.catalogTabAll,
  CatalogTab.active => l10n.catalogTabActive,
  CatalogTab.draft => l10n.catalogTabDraft,
  CatalogTab.archived => l10n.catalogTabArchived,
};

String stockFilterLabel(AppLocalizations l10n, StockFilter filter) =>
    switch (filter) {
      StockFilter.any => l10n.catalogStockAny,
      StockFilter.inStock => l10n.catalogStockIn,
      StockFilter.low => l10n.catalogStockLow,
      StockFilter.out => l10n.catalogStockOut,
    };

/// The A-05 stock pill: "52", "52 · 1 out", "4 · low", "Out of stock",
/// "Not stocked".
(String, KTone) stockPill(AppLocalizations l10n, CatalogListItem item) =>
    switch (item.stock) {
      StockState.none => (l10n.catalogNotStocked, KTone.gray),
      StockState.out => (l10n.catalogStockOut, KTone.red),
      StockState.low when item.outCount > 0 => (
        l10n.catalogStockSomeOut(item.available, item.outCount),
        KTone.amber,
      ),
      StockState.low => (l10n.catalogStockLowPill(item.available), KTone.amber),
      StockState.inStock => ('${item.available}', KTone.green),
    };

/// "$49.00" or "$9.90 – $12.50"; "—" without a price.
String priceRange(AppLocalizations l10n, int? min, int? max) {
  if (min == null) return '—';
  if (max == null || max == min) return formatUsd(min);
  return l10n.catalogPriceRange(formatUsd(min), formatUsd(max));
}

/// The A-05b per-variant pill.
(String, KTone) variantStockPill(AppLocalizations l10n, VariantDraft v) {
  if (v.available <= 0) return (l10n.catalogStockOutShort, KTone.red);
  if (v.available <= v.lowStockAt) {
    return (l10n.catalogStockLowShort, KTone.amber);
  }
  return (l10n.catalogStockOk, KTone.green);
}

/// The message under a field the server or the editor rejected.
String issueMessage(AppLocalizations l10n, FieldIssue issue) {
  final field = issue.field;
  if (issue.code == IssueCode.required) {
    if (field == 'name.en') return l10n.catalogErrName;
    if (field == 'category_id' || field == 'category') {
      return l10n.catalogErrCategory;
    }
    if (field == 'rfq_min_qty') return l10n.catalogErrMinQty;
    if (field.endsWith('.alt')) return l10n.catalogAltRequired;
    if (field.endsWith('.price_cents')) return l10n.catalogErrPrice;
    return l10n.catalogErrRequired;
  }
  return switch (issue.code) {
    IssueCode.tooLong => l10n.catalogErrTooLong,
    IssueCode.tooMany => l10n.catalogErrTooMany,
    IssueCode.duplicate => l10n.catalogErrDuplicate,
    _ when field.endsWith('.sku') => l10n.catalogErrSku,
    _ when field.endsWith('.price_cents') => l10n.catalogErrPrice,
    _ when field == 'category' || field == 'category_id' =>
      l10n.catalogErrCategory,
    _ => l10n.catalogErrInvalid,
  };
}

/// Toast text for an outcome that isn't a plain success.
String outcomeMessage(AppLocalizations l10n, CatalogOutcome outcome) =>
    switch (outcome) {
      CatalogSaved() => l10n.catalogSaved,
      CatalogUpdated() => l10n.catalogSaved,
      CatalogInvalid() => l10n.catalogFixErrors,
      CatalogSkuTaken(:final sku) => l10n.catalogSkuTaken(sku),
      CatalogRefused(reason: CatalogRefusal.notFound) => l10n.catalogNotFound,
      CatalogRefused(reason: CatalogRefusal.forbidden) => l10n.catalogForbidden,
      CatalogRefused() => l10n.catalogErrUnknown,
    };

String importFieldLabel(AppLocalizations l10n, ImportField field) =>
    switch (field) {
      ImportField.nameEn => l10n.catalogNameEn,
      ImportField.nameKm => l10n.catalogNameKm,
      ImportField.descriptionEn => l10n.catalogFieldDescEn,
      ImportField.descriptionKm => l10n.catalogFieldDescKm,
      ImportField.brand => l10n.catalogBrand,
      ImportField.category => l10n.catalogCategory,
      ImportField.sku => l10n.catalogSku,
      ImportField.barcode => l10n.catalogBarcode,
      ImportField.priceUsd => l10n.catalogFieldPrice,
      ImportField.qty => l10n.catalogOnHand,
      ImportField.tags => l10n.catalogTags,
      ImportField.handle => l10n.catalogFieldHandle,
      ImportField.variant => l10n.catalogFieldVariant,
      ImportField.ignore => l10n.catalogFieldIgnore,
    };

/// "Row 37: SKU "MUG-4-SND" already exists".
String importRowMessage(AppLocalizations l10n, ImportRowError error) {
  final value = error.value ?? '';
  final message = switch (error.code) {
    ImportErrorCode.nameMissing => l10n.catalogImpNameMissing,
    ImportErrorCode.skuMissing => l10n.catalogImpSkuMissing,
    ImportErrorCode.skuInvalid => l10n.catalogImpSkuInvalid(value),
    ImportErrorCode.skuDuplicate => l10n.catalogImpSkuDuplicate(value),
    ImportErrorCode.skuExists => l10n.catalogImpSkuExists(value),
    ImportErrorCode.priceMissing => l10n.catalogImpPriceMissing,
    ImportErrorCode.priceInvalid => l10n.catalogImpPriceInvalid(value),
    ImportErrorCode.qtyInvalid => l10n.catalogImpQtyInvalid(value),
    ImportErrorCode.categoryMissing => l10n.catalogImpCategoryMissing,
    ImportErrorCode.categoryUnknown => l10n.catalogImpCategoryUnknown(value),
    ImportErrorCode.tooLong => l10n.catalogImpTooLong,
  };
  return l10n.catalogRowError(error.row, message);
}

String importRefusalMessage(AppLocalizations l10n, ImportRefusal reason) =>
    switch (reason) {
      ImportRefusal.empty => l10n.catalogImpEmpty,
      ImportRefusal.tooLarge => l10n.catalogImpTooLarge,
      ImportRefusal.unreadable => l10n.catalogImpUnreadable,
      ImportRefusal.noMapping => l10n.catalogImportMissing(''),
      ImportRefusal.forbidden => l10n.catalogForbidden,
      ImportRefusal.unknown => l10n.catalogErrUnknown,
    };

/// "12.50" → 1250; null when it isn't an amount with at most two decimals.
int? parseUsdCents(String text) {
  final clean = text.trim().replaceAll(',', '').replaceFirst(r'$', '');
  if (!RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(clean)) return null;
  final parts = clean.split('.');
  final cents = parts.length == 1 ? '00' : parts[1].padRight(2, '0');
  return int.parse(parts[0]) * 100 + int.parse(cents);
}

/// 1250 → "12.50" for an input field.
String centsInput(int? cents) => cents == null
    ? ''
    : '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
