import { test } from 'node:test';
import assert from 'node:assert/strict';

import { groupQueue, nextActions, orderLabel } from '../js/kitchen-model.js';

const item = (overrides) => ({
  itemId: 'i',
  orderId: 'o-1',
  orderNumber: 1,
  orderKind: 'dine_in',
  tableName: 'Mesa 1',
  productName: 'Mofongo',
  quantityMilli: 1000,
  status: 'sent',
  sentAt: '2026-09-11T15:00:00.000Z',
  ...overrides,
});

test('agrupa por orden y atiende primero lo que lleva más tiempo', () => {
  const orders = groupQueue([
    item({ itemId: 'a', orderId: 'o-2', orderNumber: 2, tableName: 'Mesa 5', sentAt: '2026-09-11T15:10:00.000Z' }),
    item({ itemId: 'b', orderId: 'o-1', sentAt: '2026-09-11T15:05:00.000Z' }),
    item({ itemId: 'c', orderId: 'o-1', sentAt: '2026-09-11T15:01:00.000Z' }),
  ]);

  assert.deepEqual(
    orders.map((order) => order.orderNumber),
    [1, 2],
  );
  assert.equal(orders[0].items.length, 2);
  assert.equal(orders[0].oldestSentAt, '2026-09-11T15:01:00.000Z');
});

test('los estados solo avanzan', () => {
  assert.deepEqual(nextActions('sent'), ['preparing', 'ready']);
  assert.deepEqual(nextActions('preparing'), ['ready']);
  assert.deepEqual(nextActions('ready'), ['served']);
  assert.deepEqual(nextActions('served'), []);
  assert.deepEqual(nextActions('cancelled'), []);
});

test('nombre de la orden según el tipo', () => {
  assert.equal(orderLabel({ orderKind: 'dine_in', tableName: 'Mesa 4' }), 'Mesa 4');
  assert.equal(orderLabel({ orderKind: 'takeout' }), 'Para llevar');
  assert.equal(orderLabel({ orderKind: 'delivery' }), 'Delivery');
});
