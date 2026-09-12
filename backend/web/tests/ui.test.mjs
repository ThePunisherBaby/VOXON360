import { test } from 'node:test';
import assert from 'node:assert/strict';

import { minutesSince, paymentLabel, roleLabel } from '../js/ui.js';

test('minutos de espera', () => {
  const now = Date.parse('2026-09-11T15:30:00.000Z');
  assert.equal(minutesSince('2026-09-11T15:00:00.000Z', now), 30);
  assert.equal(minutesSince('2026-09-11T15:29:59.000Z', now), 0);
  assert.equal(minutesSince('2026-09-11T16:00:00.000Z', now), 0);
  assert.equal(minutesSince('no es fecha', now), 0);
});

test('nombres en español de pagos y roles', () => {
  assert.equal(paymentLabel('credit'), 'Fiao');
  assert.equal(paymentLabel('cash'), 'Efectivo');
  assert.equal(roleLabel('waiter'), 'Mesero');
  assert.equal(roleLabel('desconocido'), 'desconocido');
});
