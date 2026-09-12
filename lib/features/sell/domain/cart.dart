/// Error al armar la venta; `code` se traduce en la interfaz.
class CartException implements Exception {
  const CartException(this.code);

  /// whole_units, invalid_quantity, insufficient_cash o customer_required.
  final String code;

  @override
  String toString() => 'CartException($code)';
}

class CartLine {
  const CartLine({
    required this.productId,
    required this.name,
    required this.unit,
    required this.unitPriceCents,
    required this.allowsFraction,
    required this.quantityMilli,
  });

  /// Producto como lo devuelve catalog.products.list.
  factory CartLine.fromProduct(
    Map<String, dynamic> product,
    int quantityMilli,
  ) => CartLine(
    productId: product['id'] as String,
    name: product['name'] as String,
    unit: product['unit'] as String? ?? 'unit',
    unitPriceCents: product['priceCents'] as int,
    allowsFraction: product['allowsFraction'] as bool? ?? false,
    quantityMilli: quantityMilli,
  );

  final String productId;
  final String name;
  final String unit;
  final int unitPriceCents;
  final bool allowsFraction;
  final int quantityMilli;

  /// Importe estimado mientras llega la cotización del motor.
  int get estimatedCents => (unitPriceCents * quantityMilli + 500) ~/ 1000;

  CartLine withQuantity(int milli) => CartLine(
    productId: productId,
    name: name,
    unit: unit,
    unitPriceCents: unitPriceCents,
    allowsFraction: allowsFraction,
    quantityMilli: milli,
  );
}

/// Carrito inmutable: cada cambio devuelve uno nuevo. Solo guarda productos y
/// cantidades; los totales oficiales los calcula el motor (sales.quote).
class Cart {
  const Cart([this.lines = const []]);

  final List<CartLine> lines;

  bool get isEmpty => lines.isEmpty;

  int get estimatedCents =>
      lines.fold(0, (total, line) => total + line.estimatedCents);

  Cart add(Map<String, dynamic> product, {int quantityMilli = 1000}) {
    final line = CartLine.fromProduct(product, quantityMilli);
    _validate(line.allowsFraction, quantityMilli);
    final index = lines.indexWhere((item) => item.productId == line.productId);
    if (index < 0) return Cart([...lines, line]);
    final updated = lines[index].withQuantity(
      lines[index].quantityMilli + quantityMilli,
    );
    return Cart([...lines]..[index] = updated);
  }

  /// Cambia la cantidad; cero quita la línea.
  Cart setQuantity(String productId, int quantityMilli) {
    final index = lines.indexWhere((item) => item.productId == productId);
    if (index < 0) return this;
    if (quantityMilli == 0) return remove(productId);
    _validate(lines[index].allowsFraction, quantityMilli);
    return Cart([...lines]..[index] = lines[index].withQuantity(quantityMilli));
  }

  Cart remove(String productId) =>
      Cart(lines.where((line) => line.productId != productId).toList());

  /// Líneas para sales.quote y sales.complete.
  List<Map<String, Object?>> toSaleLines() => [
    for (final line in lines)
      {'productId': line.productId, 'quantityMilli': line.quantityMilli},
  ];

  static void _validate(bool allowsFraction, int quantityMilli) {
    if (quantityMilli <= 0) throw const CartException('invalid_quantity');
    if (!allowsFraction && quantityMilli % 1000 != 0) {
      throw const CartException('whole_units');
    }
  }
}
