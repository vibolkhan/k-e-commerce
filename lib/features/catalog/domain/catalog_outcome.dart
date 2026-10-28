import 'product_draft.dart';

/// What catalog-manage answered (HTTP 200 with a `status`).
sealed class CatalogOutcome {
  const CatalogOutcome();

  factory CatalogOutcome.fromJson(Map<String, dynamic> json) =>
      switch (json['status']) {
        'saved' => CatalogSaved(json['id'] as String),
        'updated' => CatalogUpdated((json['count'] as num?)?.toInt() ?? 0),
        'invalid' => CatalogInvalid([
          for (final e in (json['errors'] as List? ?? const []))
            if (e is Map)
              FieldIssue(
                e['field']?.toString() ?? 'product',
                IssueCode.fromWire(e['code']),
              ),
        ]),
        'sku_taken' => CatalogSkuTaken(json['sku']?.toString() ?? ''),
        'not_found' => const CatalogRefused(CatalogRefusal.notFound),
        'forbidden' => const CatalogRefused(CatalogRefusal.forbidden),
        _ => const CatalogRefused(CatalogRefusal.unknown),
      };
}

class CatalogSaved extends CatalogOutcome {
  const CatalogSaved(this.id);
  final String id;
}

class CatalogUpdated extends CatalogOutcome {
  const CatalogUpdated(this.count);
  final int count;
}

class CatalogInvalid extends CatalogOutcome {
  const CatalogInvalid(this.issues);
  final List<FieldIssue> issues;
}

class CatalogSkuTaken extends CatalogOutcome {
  const CatalogSkuTaken(this.sku);
  final String sku;
}

enum CatalogRefusal { notFound, forbidden, unknown }

class CatalogRefused extends CatalogOutcome {
  const CatalogRefused(this.reason);
  final CatalogRefusal reason;
}
