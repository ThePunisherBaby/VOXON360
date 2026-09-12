import 'package:flutter_test/flutter_test.dart';

import 'package:voxon90/features/sell/domain/cart.dart';
import 'package:voxon90/features/tables/domain/order_rules.dart';

void main() {
  final order = <String, dynamic>{
    'items': [
      {'id': 'a', 'status': 'pending'},
      {'id': 'b', 'status': 'sent'},
      {'id': 'c', 'status': 'cancelled'},
      {'id': 'd', 'status': 'pending'},
    ],
  };

  test('lo cancelado no cuenta y lo pendiente se puede enviar', () {
    expect(activeItems(order).map((item) => item['id']), ['a', 'b', 'd']);
    expect(pendingItemCount(order), 2);
    expect(pendingItemCount(const {}), 0);
  });

  test('solo el dueño o un gerente cancelan lo que ya se envió', () {
    expect(canCancelItem('pending', 'waiter'), isTrue);
    expect(canCancelItem('sent', 'waiter'), isFalse);
    expect(canCancelItem('sent', 'cashier'), isFalse);
    expect(canCancelItem('preparing', 'manager'), isTrue);
    expect(canCancelItem('ready', 'owner'), isTrue);
    expect(canCancelItem('served', 'owner'), isFalse);
  });

  test('las órdenes sin mesa son para llevar o delivery', () {
    final orders = <Map<String, dynamic>>[
      {'orderId': '1', 'kind': 'dine_in'},
      {'orderId': '2', 'kind': 'takeout'},
      {'orderId': '3', 'kind': 'delivery'},
    ];
    expect(ordersWithoutTable(orders).map((o) => o['orderId']), ['2', '3']);
  });

  group('pagos del cobro', () {
    test('efectivo exacto o con vuelto', () {
      expect(checkoutPayments(method: 'cash', totalCents: 128000), [
        {'method': 'cash', 'amountCents': 128000},
      ]);
      expect(
        checkoutPayments(
          method: 'cash',
          totalCents: 128000,
          receivedCents: 150000,
        ),
        [
          {'method': 'cash', 'amountCents': 150000},
        ],
      );
    });

    test('efectivo que no alcanza', () {
      expect(
        () => checkoutPayments(
          method: 'cash',
          totalCents: 128000,
          receivedCents: 100000,
        ),
        throwsA(
          isA<CartException>().having(
            (error) => error.code,
            'code',
            'insufficient_cash',
          ),
        ),
      );
    });

    test('tarjeta y transferencia cobran el total exacto', () {
      expect(
        checkoutPayments(
          method: 'card',
          totalCents: 128000,
          receivedCents: 500000,
        ),
        [
          {'method': 'card', 'amountCents': 128000},
        ],
      );
      expect(checkoutPayments(method: 'transfer', totalCents: 0), isEmpty);
      expect(checkoutPayments(method: 'cash', totalCents: 0), isEmpty);
    });
  });
}
