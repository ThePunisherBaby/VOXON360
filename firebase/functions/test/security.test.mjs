// Pruebas de lo que protege los PIN y los códigos de caja.
//   npm test   (compila y corre)
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { CODE_ALPHABET, hashPin, isValidPin, randomCode, verifyPin } from '../lib/security.js';

test('el PIN tiene de 4 a 6 números', () => {
  assert.equal(isValidPin('1234'), true);
  assert.equal(isValidPin('123456'), true);
  assert.equal(isValidPin('123'), false);
  assert.equal(isValidPin('1234567'), false);
  assert.equal(isValidPin('12a4'), false);
  assert.equal(isValidPin(1234), false);
});

test('el PIN se guarda con hash y sal propia', () => {
  const stored = hashPin('2468', undefined, 1000);
  assert.notEqual(stored.hash, '2468');
  assert.equal(stored.hash.length, 64);
  assert.equal(verifyPin('2468', stored), true);
  assert.equal(verifyPin('2469', stored), false);

  const other = hashPin('2468', undefined, 1000);
  assert.notEqual(other.salt, stored.salt);
  assert.notEqual(other.hash, stored.hash);
});

test('un hash dañado nunca abre la caja', () => {
  assert.equal(verifyPin('2468', { hash: '', salt: 'x', iterations: 1000 }), false);
  assert.equal(verifyPin('2468', { hash: 'abcd', salt: 'x', iterations: 1000 }), false);
});

test('coincide con el vector conocido de PBKDF2-HMAC-SHA256', () => {
  // RFC 7914, sección 11: P="passwd", S="salt", c=1, dkLen=64 (se comparan los primeros 32 bytes).
  const { hash } = hashPin('passwd', 'salt', 1);
  assert.equal(hash, '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc');
});

test('los códigos usan solo caracteres fáciles de dictar', () => {
  const codes = new Set();
  for (let i = 0; i < 2000; i++) {
    const code = randomCode();
    assert.match(code, /^[A-HJ-NP-Z2-9]{8}$/);
    codes.add(code);
  }
  assert.equal(codes.size, 2000, 'no deberían repetirse en 2000 intentos');
  assert.equal(CODE_ALPHABET.includes('O') || CODE_ALPHABET.includes('0'), false);
});
