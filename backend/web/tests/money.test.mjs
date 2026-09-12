import { test } from 'node:test';
import assert from 'node:assert/strict';

import { formatMoney, formatQuantity, lineAmount, parseMoney, parseQuantity, unitLabel } from '../js/money.js';

test('formatea montos en pesos dominicanos', () => {
  assert.equal(formatMoney(125075), 'RD$1,250.75');
  assert.equal(formatMoney(5), 'RD$0.05');
  assert.equal(formatMoney(-350), '-RD$3.50');
  assert.equal(formatMoney(123456789), 'RD$1,234,567.89');
  assert.equal(formatMoney(0), 'RD$0.00');
  assert.throws(() => formatMoney(1.5), TypeError);
});

test('lee los montos que escribe el cajero', () => {
  assert.equal(parseMoney('1,250.75'), 125075);
  assert.equal(parseMoney('RD$ 99'), 9900);
  assert.equal(parseMoney('150.5'), 15050);
  assert.equal(parseMoney('-3.25'), -325);
  assert.equal(parseMoney('abc'), null);
  assert.equal(parseMoney('1.234'), null);
  assert.equal(parseMoney(''), null);
});

test('cantidades en milésimas', () => {
  assert.equal(formatQuantity(500), '0.5');
  assert.equal(formatQuantity(1250), '1.25');
  assert.equal(formatQuantity(3000), '3');
  assert.equal(parseQuantity('0.5'), 500);
  assert.equal(parseQuantity(' 2 '), 2000);
  assert.equal(parseQuantity('1.2345'), null);
  assert.equal(parseQuantity('media'), null);
});

test('importe de línea y unidades', () => {
  assert.equal(lineAmount(3500, 500), 1750);
  assert.equal(lineAmount(10000, 333), 3330);
  assert.equal(unitLabel('pound'), 'lb');
  assert.equal(unitLabel('otra'), 'otra');
});
