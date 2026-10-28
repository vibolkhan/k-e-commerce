import 'dart:convert';

/// One line in the shopper's cart: a variant and how many. Prices are not
/// kept here: the server prices the cart at checkout (F16, F17).
class CartLine {
  const CartLine({
    required this.variantId,
    required this.productId,
    required this.qty,
  });

  factory CartLine.fromJson(Map<String, dynamic> json) => CartLine(
    variantId: json['variant_id'] as String,
    productId: json['product_id'] as String,
    qty: (json['qty'] as num).toInt(),
  );

  final String variantId;
  final String productId;
  final int qty;

  Map<String, Object> toJson() => {
    'variant_id': variantId,
    'product_id': productId,
    'qty': qty,
  };

  CartLine withQty(int qty) =>
      CartLine(variantId: variantId, productId: productId, qty: qty);

  @override
  bool operator ==(Object other) =>
      other is CartLine &&
      other.variantId == variantId &&
      other.productId == productId &&
      other.qty == qty;

  @override
  int get hashCode => Object.hash(variantId, productId, qty);
}

/// Adds [line] to [lines], merging with the same variant, with the line's
/// quantity kept within [max] (the product's per-order limit and stock as
/// the page knew them; the server checks again at checkout).
List<CartLine> addLine(
  List<CartLine> lines,
  CartLine line, {
  required int max,
}) {
  final i = lines.indexWhere((l) => l.variantId == line.variantId);
  if (i < 0) {
    return [...lines, line.withQty(line.qty.clamp(1, max < 1 ? 1 : max))];
  }
  final merged = (lines[i].qty + line.qty).clamp(1, max < 1 ? 1 : max);
  return [...lines]..[i] = lines[i].withQty(merged);
}

/// How many of [variantId] the cart already holds.
int qtyInCart(List<CartLine> lines, String variantId) =>
    lines.where((l) => l.variantId == variantId).fold(0, (n, l) => n + l.qty);

String encodeCart(List<CartLine> lines) =>
    jsonEncode([for (final l in lines) l.toJson()]);

List<CartLine> decodeCart(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    return [
      for (final l in jsonDecode(raw) as List)
        CartLine.fromJson(l as Map<String, dynamic>),
    ];
  } on Object {
    return const [];
  }
}
