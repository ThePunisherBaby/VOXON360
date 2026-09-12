import { test } from 'node:test';
import assert from 'node:assert/strict';

import { ApiClient, ApiError } from '../js/api.js';

function fakeFetch(responses) {
  const calls = [];
  const fetch = async (url, options) => {
    calls.push({ url, options });
    const next = responses.shift();
    if (next instanceof Error) {
      throw next;
    }
    return { status: next.status, json: async () => next.body };
  };
  fetch.calls = calls;
  return fetch;
}

function memoryStorage() {
  const values = new Map();
  return {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, String(value)),
    removeItem: (key) => values.delete(key),
  };
}

const loginResponse = {
  status: 200,
  body: { ok: true, result: { token: 't-1', user: { id: 'u-1', name: 'Ana', role: 'owner' } } },
};

test('el login guarda la sesión y call envía el token', async () => {
  const fetch = fakeFetch([loginResponse, { status: 200, body: { ok: true, result: [{ id: 'u-1' }] } }]);
  const storage = memoryStorage();
  const api = new ApiClient({ fetch, storage });

  const user = await api.login('1111');
  assert.equal(user.name, 'Ana');
  assert.equal(api.isLoggedIn, true);

  const users = await api.call('users.list');
  assert.deepEqual(users, [{ id: 'u-1' }]);
  assert.equal(fetch.calls[1].url, '/api/call');
  assert.equal(fetch.calls[1].options.headers.Authorization, 'Bearer t-1');
  assert.deepEqual(JSON.parse(fetch.calls[1].options.body), { method: 'users.list', params: {} });

  // Otra pestaña con el mismo almacenamiento recupera la sesión.
  assert.equal(new ApiClient({ fetch, storage }).user.name, 'Ana');
});

test('los errores del motor llegan como ApiError y un 401 cierra la sesión', async () => {
  const fetch = fakeFetch([
    loginResponse,
    { status: 409, body: { ok: false, error: { code: 'cash_session_closed', message: 'No hay una caja abierta' } } },
    { status: 401, body: { ok: false, error: { code: 'unauthorized', message: 'Inicia sesión con tu PIN' } } },
  ]);
  const api = new ApiClient({ fetch, storage: memoryStorage() });
  let unauthorized = 0;
  api.onUnauthorized(() => {
    unauthorized += 1;
  });
  await api.login('1111');

  await assert.rejects(api.call('cash.movement', {}), (error) => {
    assert.ok(error instanceof ApiError);
    assert.equal(error.code, 'cash_session_closed');
    assert.equal(error.status, 409);
    return true;
  });
  assert.equal(api.isLoggedIn, true);

  await assert.rejects(api.call('users.list'), { code: 'unauthorized' });
  assert.equal(api.isLoggedIn, false);
  assert.equal(unauthorized, 1);
});

test('un PIN incorrecto no dispara el aviso de sesión vencida', async () => {
  const fetch = fakeFetch([{ status: 401, body: { ok: false, error: { code: 'unauthorized', message: 'PIN incorrecto' } } }]);
  const api = new ApiClient({ fetch, storage: memoryStorage() });
  let unauthorized = 0;
  api.onUnauthorized(() => {
    unauthorized += 1;
  });
  await assert.rejects(api.login('9999'), { code: 'unauthorized', message: 'PIN incorrecto' });
  assert.equal(unauthorized, 0);
});

test('sin conexión con la caja principal da un error claro', async () => {
  const api = new ApiClient({ fetch: fakeFetch([new TypeError('Failed to fetch')]), storage: memoryStorage() });
  await assert.rejects(api.health(), { code: 'offline' });
});

test('una respuesta que no es JSON se informa como inválida', async () => {
  const fetch = async () => ({ status: 502, json: async () => { throw new SyntaxError('no json'); } });
  const api = new ApiClient({ fetch, storage: memoryStorage() });
  await assert.rejects(api.health(), { code: 'invalid_response', status: 502 });
});

test('logout limpia la sesión aunque el servidor no responda', async () => {
  const fetch = fakeFetch([loginResponse, new TypeError('Failed to fetch')]);
  const api = new ApiClient({ fetch, storage: memoryStorage() });
  await api.login('1111');
  await api.logout();
  assert.equal(api.isLoggedIn, false);
});
