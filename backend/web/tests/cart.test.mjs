import { test } from 'node:test';
import assert from 'node:assert/strict';

import { Cart } from '../js/cart.js';

const soda = { id: 'p-soda', name: 'Refresco', priceCents: 5900, unit: 'unit', allowsFraction: false };
const rice = { id: 'p-rice', name: 'Arroz', priceCents: 3500, unit: 'pound', allowsFraction: true };

test('agrega productos, suma cantidades y estima el bruto', () => {
  const cart = new Cart();
  cart.add(soda);
  cart.add(soda);
  cart.add(rice, 500);

  assert.equal(cart.lines.length, 2);
  assert.equal(cart.lines[0].quantityMilli, 2000);
  assert.equal(cart.estimatedGrossCents(), 13550);
  assert.deepEqual(cart.toSaleLines(), [
    { productId: 'p-soda', quantityMilli: 2000 },
    { productId: 'p-rice', quantityMilli: 500 },
  ]);
});

test('respeta los productos que se venden por unidades enteras', () => {
  const cart = new Cart();
  assert.throws(() => cart.add(soda, 500), /unidades enteras/);
  cart.add(soda);
  assert.throws(() => cart.setQuantity('p-soda', 1500), /unidades enteras/);
  assert.throws(() => cart.add(rice, 0), /mayor que cero/);
});

test('cambiar a cero quita la línea y vaciar deja el carrito limpio', () => {
  const cart = new Cart();
  cart.add(soda);
  cart.add(rice, 2000);
  cart.setQuantity('p-soda', 0);
  assert.deepEqual(
    cart.lines.map((line) => line.productId),
    ['p-rice'],
  );

  // Las líneas devueltas son copias: modificarlas no cambia el carrito.
  cart.lines[0].quantityMilli = 1;
  assert.equal(cart.lines[0].quantityMilli, 2000);

  cart.clear();
  assert.equal(cart.isEmpty, true);
});
