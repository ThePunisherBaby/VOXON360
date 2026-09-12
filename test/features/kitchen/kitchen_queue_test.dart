import 'package:flutter_test/flutter_test.dart';

import 'package:voxon90/features/kitchen/domain/kitchen_queue.dart';

Map<String, dynamic> item(Map<String, dynamic> overrides) => {
  'itemId': 'i',
  'orderId': 'o-1',
  'orderNumber': 1,
  'orderKind': 'dine_in',
  'tableName': 'Mesa 1',
  'productName': 'Mofongo',
  'quantityMilli': 1000,
  'status': 'sent',
  'sentAt': '2026-09-11T15:00:00.000Z',
  ...overrides,
};

void main() {
  test('agrupa por orden y atiende primero lo que lleva más tiempo', () {
    final orders = groupKitchenQueue([
      item({
        'itemId': 'a',
        'orderId': 'o-2',
        'orderNumber': 2,
        'sentAt': '2026-09-11T15:10:00.000Z',
      }),
      item({'itemId': 'b', 'sentAt': '2026-09-11T15:05:00.000Z'}),
      item({'itemId': 'c', 'sentAt': '2026-09-11T15:01:00.000Z'}),
    ]);

    expect(orders.map((order) => order.orderNumber), [1, 2]);
    expect(orders.first.items, hasLength(2));
    expect(
      orders.first.oldestSentAt,
      DateTime.parse('2026-09-11T15:01:00.000Z'),
    );
  });

  test('los estados solo avanzan', () {
    expect(nextKitchenActions('sent'), ['preparing', 'ready']);
    expect(nextKitchenActions('preparing'), ['ready']);
    expect(nextKitchenActions('ready'), ['served']);
    expect(nextKitchenActions('served'), isEmpty);
  });

  test('minutos de espera', () {
    final now = DateTime.parse('2026-09-11T15:30:00.000Z');
    expect(minutesWaiting(DateTime.parse('2026-09-11T15:00:00.000Z'), now), 30);
    expect(minutesWaiting(DateTime.parse('2026-09-11T16:00:00.000Z'), now), 0);
    expect(minutesWaiting(null, now), 0);
  });
}
