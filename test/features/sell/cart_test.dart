import 'package:flutter_test/flutter_test.dart';

import 'package:voxon90/core/format/money_format.dart';
import 'package:voxon90/features/sell/domain/cart.dart';

const soda = {
  'id': 'p-soda',
  'name': 'Refresco',
  'priceCents': 5900,
  'unit': 'unit',
  'allowsFraction': false,
};
const rice = {
  'id': 'p-rice',
  'name': 'Arroz',
  'priceCents': 3500,
  'unit': 'pound',
  'allowsFraction': true,
};

void main() {
  test('agrega productos, suma cantidades y estima el importe', () {
    final cart = const Cart().add(soda).add(soda).add(rice, quantityMilli: 500);

    expect(cart.lines, hasLength(2));
    expect(cart.lines.first.quantityMilli, 2000);
    expect(cart.estimatedCents, 13550);
    expect(cart.toSaleLines(), [
      {'productId': 'p-soda', 'quantityMilli': 2000},
      {'productId': 'p-rice', 'quantityMilli': 500},
    ]);
  });

  test('respeta las unidades enteras y rechaza cantidades inválidas', () {
    expect(
      () => const Cart().add(soda, quantityMilli: 500),
      throwsA(
        isA<CartException>().having((e) => e.code, 'code', 'whole_units'),
      ),
    );
    final cart = const Cart().add(soda);
    expect(
      () => cart.setQuantity('p-soda', 1500),
      throwsA(isA<CartException>()),
    );
    expect(
      () => cart.add(rice, quantityMilli: 0),
      throwsA(
        isA<CartException>().having((e) => e.code, 'code', 'invalid_quantity'),
      ),
    );
  });

  test('poner cero quita la línea y el carrito original no cambia', () {
    final original = const Cart().add(soda).add(rice, quantityMilli: 2000);
    final updated = original.setQuantity('p-soda', 0);

    expect(updated.lines.map((line) => line.productId), ['p-rice']);
    expect(original.lines, hasLength(2));
    expect(updated.remove('p-rice').isEmpty, isTrue);
  });

  test('formato de dinero y cantidades', () {
    expect(formatMoney(125075), 'RD\$1,250.75');
    expect(formatMoney(5), 'RD\$0.05');
    expect(formatMoney(-350), '-RD\$3.50');
    expect(formatMoney(123456789), 'RD\$1,234,567.89');
    expect(parseMoney('1,250.75'), 125075);
    expect(parseMoney('abc'), isNull);
    expect(formatQuantity(500), '0.5');
    expect(parseQuantity('0,5'), 500);
    expect(parseQuantity('-1'), isNull);
    expect(unitLabel('pound'), 'lb');
  });
}
