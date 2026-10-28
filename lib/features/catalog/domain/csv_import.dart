/// A-05d CSV import: the client reads the header and a sample row to match
/// columns; catalog-import parses and checks the whole file.
library;

/// What a column can be imported as (catalog-import `IMPORT_FIELDS`).
enum ImportField {
  nameEn('name_en'),
  nameKm('name_km'),
  descriptionEn('description_en'),
  descriptionKm('description_km'),
  brand('brand'),
  category('category'),
  sku('sku'),
  barcode('barcode'),
  priceUsd('price_usd'),
  qty('qty'),
  tags('tags'),
  handle('handle'),
  variant('variant'),
  ignore('ignore');

  const ImportField(this.wire);
  final String wire;

  static const required = [nameEn, sku, priceUsd, category];

  static ImportField fromWire(Object? value) =>
      values.firstWhere((f) => f.wire == value, orElse: () => ignore);
}

/// The import template's column names and the usual alternatives.
const _aliases = <ImportField, List<String>>{
  ImportField.nameEn: ['name', 'name_en', 'product', 'product_name', 'title'],
  ImportField.nameKm: ['name_km', 'khmer_name', 'name_kh'],
  ImportField.descriptionEn: ['description', 'description_en', 'desc'],
  ImportField.descriptionKm: ['description_km', 'description_kh'],
  ImportField.brand: ['brand', 'make'],
  ImportField.category: ['category', 'category_slug', 'collection'],
  ImportField.sku: ['sku', 'item_code', 'code'],
  ImportField.barcode: ['barcode', 'ean', 'upc', 'gtin'],
  ImportField.priceUsd: ['price', 'price_usd', 'usd', 'retail_price'],
  ImportField.qty: ['qty', 'quantity', 'stock', 'on_hand'],
  ImportField.tags: ['tags', 'labels'],
  ImportField.handle: ['handle', 'group', 'product_handle', 'parent'],
  ImportField.variant: ['variant', 'options', 'option', 'attributes'],
};

/// Best guess for each column; anything unknown or already taken is
/// "Don't import".
Map<String, ImportField> autoMapping(List<String> header) {
  String norm(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'[\s\-()]+'), '_');
  final taken = <ImportField>{};
  return {
    for (final column in header)
      column: () {
        final key = norm(column);
        for (final entry in _aliases.entries) {
          if (!taken.contains(entry.key) && entry.value.contains(key)) {
            taken.add(entry.key);
            return entry.key;
          }
        }
        return ImportField.ignore;
      }(),
  };
}

/// Required fields no column is mapped to yet.
List<ImportField> missingFields(Map<String, ImportField> mapping) => [
  for (final f in ImportField.required)
    if (!mapping.values.contains(f)) f,
];

/// The first records of a CSV file: enough to show the header, a sample
/// value per column and how many rows there are. Handles quoted fields with
/// commas, quotes and line breaks.
class CsvHead {
  const CsvHead({
    required this.header,
    required this.sample,
    required this.rowCount,
    required this.emptyCounts,
  });

  final List<String> header;

  /// The first data row, padded to the header's length.
  final List<String> sample;
  final int rowCount;

  /// Per column, how many rows leave it empty ("(empty in 84 rows)").
  final List<int> emptyCounts;

  static CsvHead? parse(String text) {
    final records = parseCsv(text);
    if (records.isEmpty) return null;
    final header = [for (final h in records.first) h.trim()];
    if (header.every((h) => h.isEmpty)) return null;
    final rows = [
      for (final r in records.skip(1))
        if (r.any((c) => c.trim().isNotEmpty)) r,
    ];
    String at(List<String> row, int i) => i < row.length ? row[i].trim() : '';
    return CsvHead(
      header: header,
      sample: [
        for (var i = 0; i < header.length; i++)
          rows.isEmpty ? '' : at(rows.first, i),
      ],
      rowCount: rows.length,
      emptyCounts: [
        for (var i = 0; i < header.length; i++)
          rows.where((r) => at(r, i).isEmpty).length,
      ],
    );
  }
}

/// RFC 4180 records. Quotes may wrap a field; `""` inside is a quote.
List<List<String>> parseCsv(String text) {
  final input = text.startsWith('﻿') ? text.substring(1) : text;
  final records = <List<String>>[];
  var record = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var i = 0;
  while (i < input.length) {
    final ch = input[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        quoted = false;
      } else {
        field.write(ch);
      }
    } else if (ch == '"' && field.isEmpty) {
      quoted = true;
    } else if (ch == ',') {
      record.add(field.toString());
      field.clear();
    } else if (ch == '\n' || ch == '\r') {
      record.add(field.toString());
      field.clear();
      records.add(record);
      record = <String>[];
      if (ch == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
    } else {
      field.write(ch);
    }
    i++;
  }
  if (field.isNotEmpty || record.isNotEmpty) {
    record.add(field.toString());
    records.add(record);
  }
  return records;
}

enum ImportErrorCode {
  nameMissing('name_missing'),
  skuMissing('sku_missing'),
  skuInvalid('sku_invalid'),
  skuDuplicate('sku_duplicate'),
  skuExists('sku_exists'),
  priceMissing('price_missing'),
  priceInvalid('price_invalid'),
  qtyInvalid('qty_invalid'),
  categoryMissing('category_missing'),
  categoryUnknown('category_unknown'),
  tooLong('too_long');

  const ImportErrorCode(this.wire);
  final String wire;

  static ImportErrorCode fromWire(Object? value) =>
      values.firstWhere((c) => c.wire == value, orElse: () => tooLong);
}

class ImportRowError {
  const ImportRowError(this.row, this.code, [this.value]);

  factory ImportRowError.fromJson(Map<String, dynamic> json) => ImportRowError(
    (json['row'] as num).toInt(),
    ImportErrorCode.fromWire(json['code']),
    json['value'] as String?,
  );

  /// Spreadsheet row: the header is row 1.
  final int row;
  final ImportErrorCode code;
  final String? value;
}

/// What catalog-import answered.
sealed class ImportOutcome {
  const ImportOutcome();

  factory ImportOutcome.fromJson(Map<String, dynamic> json) {
    List<ImportRowError> errors() => [
      for (final e in (json['errors'] as List? ?? const []))
        ImportRowError.fromJson(e as Map<String, dynamic>),
    ];
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    return switch (json['status']) {
      'preview' => ImportPreview(
        rows: n('rows'),
        valid: n('valid'),
        products: n('products'),
        errors: errors(),
      ),
      'imported' => ImportDone(
        products: n('products'),
        variants: n('variants'),
        skipped: n('skipped'),
        errors: errors(),
      ),
      'empty' => const ImportRefused(ImportRefusal.empty),
      'too_large' => const ImportRefused(ImportRefusal.tooLarge),
      'unreadable' => const ImportRefused(ImportRefusal.unreadable),
      'no_mapping' => const ImportRefused(ImportRefusal.noMapping),
      'forbidden' => const ImportRefused(ImportRefusal.forbidden),
      _ => const ImportRefused(ImportRefusal.unknown),
    };
  }
}

class ImportPreview extends ImportOutcome {
  const ImportPreview({
    required this.rows,
    required this.valid,
    required this.products,
    required this.errors,
  });

  final int rows;
  final int valid;
  final int products;
  final List<ImportRowError> errors;
}

class ImportDone extends ImportOutcome {
  const ImportDone({
    required this.products,
    required this.variants,
    required this.skipped,
    required this.errors,
  });

  final int products;
  final int variants;
  final int skipped;
  final List<ImportRowError> errors;
}

enum ImportRefusal {
  empty,
  tooLarge,
  unreadable,
  noMapping,
  forbidden,
  unknown,
}

class ImportRefused extends ImportOutcome {
  const ImportRefused(this.reason);
  final ImportRefusal reason;
}

/// Files the wizard accepts (catalog-import `MAX_BYTES`).
const maxImportBytes = 2 * 1024 * 1024;
