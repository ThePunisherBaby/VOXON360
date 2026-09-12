// Flujo completo contra los emuladores (Auth, Firestore con sus reglas y Functions):
// cuenta de un restaurante → caja vinculada → empleado con PIN → venta → inventario → cierre.
//   cd firebase && npm run test:functions
import assert from 'node:assert/strict';
import { before, describe, it } from 'node:test';

const PROJECT = 'demo-voxon';
const AUTH = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
const FUNCTIONS = `http://127.0.0.1:5001/${PROJECT}/us-central1`;
const FIRESTORE = `http://127.0.0.1:8080/v1/projects/${PROJECT}/databases/(default)/documents`;
/** Con este token el emulador de Firestore ignora las reglas: sirve para revisar lo que quedó guardado. */
const ADMIN = 'owner';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function signUp(email) {
  const body = email
    ? { email, password: 'ClaveDePrueba123', returnSecureToken: true }
    : { returnSecureToken: true };
  const response = await fetch(`${AUTH}/accounts:signUp?key=demo`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const json = await response.json();
  assert.ok(json.idToken, JSON.stringify(json));
  return { uid: json.localId, token: json.idToken };
}

/** Llama una función callable; devuelve {result} o {error}. */
async function call(name, token, data) {
  const response = await fetch(`${FUNCTIONS}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify({ data }),
  });
  return response.json();
}

async function callOk(name, token, data) {
  const json = await call(name, token, data);
  assert.ok(json.result, `${name}: ${JSON.stringify(json.error)}`);
  return json.result;
}

function encode(value) {
  if (value === null) return { nullValue: null };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (Number.isInteger(value)) return { integerValue: String(value) };
  if (typeof value === 'number') return { doubleValue: value };
  if (typeof value === 'string') return { stringValue: value };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(encode) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(value).map(([k, v]) => [k, encode(v)])) } };
}

function decode(typed) {
  if ('nullValue' in typed) return null;
  if ('booleanValue' in typed) return typed.booleanValue;
  if ('integerValue' in typed) return Number(typed.integerValue);
  if ('doubleValue' in typed) return typed.doubleValue;
  if ('stringValue' in typed) return typed.stringValue;
  if ('timestampValue' in typed) return typed.timestampValue;
  if ('arrayValue' in typed) return (typed.arrayValue.values ?? []).map(decode);
  if ('mapValue' in typed) {
    return Object.fromEntries(Object.entries(typed.mapValue.fields ?? {}).map(([k, v]) => [k, decode(v)]));
  }
  return undefined;
}

/** Documento como objeto, null si no existe, o {denied} si las reglas lo impiden. */
async function getDoc(path, token = ADMIN) {
  const response = await fetch(`${FIRESTORE}/${path}`, { headers: { Authorization: `Bearer ${token}` } });
  if (response.status === 404) return null;
  const json = await response.json();
  if (json.error) return { denied: json.error.status };
  return Object.fromEntries(Object.entries(json.fields ?? {}).map(([k, v]) => [k, decode(v)]));
}

async function listDocs(path) {
  const response = await fetch(`${FIRESTORE}/${path}?pageSize=100`, { headers: { Authorization: `Bearer ${ADMIN}` } });
  return (await response.json()).documents ?? [];
}

/** Escribe con el token dado (pasa por las reglas) y devuelve el código HTTP. */
async function setDoc(path, data, token) {
  const response = await fetch(`${FIRESTORE}/${path}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ fields: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, encode(v)])) }),
  });
  await response.text();
  return response.status;
}

/** Repite `check` hasta que devuelva algo, para esperar a los disparadores. */
async function eventually(check, timeoutMs = 20_000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const value = await check();
    if (value) return value;
    await sleep(300);
  }
  return null;
}

describe('un restaurante con cajas VOXON POS', () => {
  const state = {};

  before(async () => {
    state.owner = await signUp(`dueno-${Date.now()}@example.com`);
  });

  it('crear la cuenta prepara el negocio según su modo', async () => {
    const { accountId, instanceId } = await callOk('createAccount', state.owner.token, {
      accountName: 'Grupo Ana',
      instanceName: 'La Fonda',
      mode: 'restaurant',
    });
    Object.assign(state, { accountId, instanceId });

    const account = await eventually(async () => {
      const current = await getDoc(`accounts/${accountId}`);
      return current?.usage?.users === 1 ? current : null;
    });
    assert.ok(account, 'onMemberAdded debió contar al dueño una vez');
    assert.equal(account.plan.tier, 'v90');
    assert.equal(account.plan.status, 'trial');
    assert.deepEqual(account.usage, { instances: 1, users: 1, staff: 0, devices: 0 });

    const instance = await getDoc(`instances/${instanceId}`);
    assert.equal(instance.mode, 'restaurant');
    assert.equal(instance.fiscal.legalTip, true);
    assert.equal(instance.fiscal.priceMode, 'tax_excluded');
    assert.ok(instance.modules.includes('kitchen'));
    assert.equal((await listDocs(`instances/${instanceId}/categories`)).length, 6);
    assert.equal((await listDocs(`instances/${instanceId}/stations`)).length, 2);
    const branding = await getDoc(`instances/${instanceId}/settings/branding`);
    assert.equal(branding.displayName, 'La Fonda');
    assert.equal(branding.primaryColor, '#C62828');
  });

  it('un modo que todavía no está listo no se puede elegir', async () => {
    const json = await call('createAccount', state.owner.token, {
      accountName: 'Otra',
      instanceName: 'Lavandería',
      mode: 'laundry',
    });
    assert.equal(json.error?.status, 'FAILED_PRECONDITION');
  });

  it('la caja se vincula con el código y queda bloqueada sin empleado', async () => {
    const { code } = await callOk('createDeviceCode', state.owner.token, {
      instanceId: state.instanceId,
      name: 'Caja 1',
    });
    assert.match(code, /^[A-HJ-NP-Z2-9]{8}$/);

    state.device = await signUp(null);
    const enrolled = await callOk('enrollDevice', state.device.token, {
      code: `${code.slice(0, 4)}-${code.slice(4)}`.toLowerCase(),
      platform: 'windows',
    });
    assert.equal(enrolled.instanceId, state.instanceId);
    assert.equal(enrolled.instanceName, 'La Fonda');
    assert.equal(enrolled.deviceNumber, 1);

    const reused = await call('enrollDevice', (await signUp(null)).token, { code, platform: 'android' });
    assert.equal(reused.error?.status, 'NOT_FOUND', 'un código solo sirve una vez');

    const member = await getDoc(`instances/${state.instanceId}/members/${state.device.uid}`);
    assert.equal(member.role, 'locked');
    assert.equal(member.kind, 'device');

    await sleep(3000);
    const account = await getDoc(`accounts/${state.accountId}`);
    assert.equal(account.usage.devices, 1);
    assert.equal(account.usage.users, 1, 'una caja no cuenta como usuario');
  });

  it('el empleado entra con su PIN, vende y el inventario baja', async () => {
    const { staffId } = await callOk('saveStaff', state.owner.token, {
      instanceId: state.instanceId,
      name: 'Luis',
      role: 'cashier',
      pin: '2468',
    });

    const staff = await getDoc(`instances/${state.instanceId}/staff/${staffId}`, state.device.token);
    assert.equal(staff.name, 'Luis');
    assert.equal('hash' in staff, false);
    const secret = await getDoc(`instances/${state.instanceId}/staffSecrets/${staffId}`, state.device.token);
    assert.ok(secret?.denied, 'la caja no puede leer el hash del PIN');

    const locked = await setDoc(
      `instances/${state.instanceId}/sales/antes`,
      { status: 'completed', totalCents: 100 },
      state.device.token,
    );
    assert.equal(locked, 403, 'sin empleado adentro la caja no vende');

    const wrong = await call('posLogin', state.device.token, { instanceId: state.instanceId, staffId, pin: '1111' });
    assert.equal(wrong.error?.status, 'PERMISSION_DENIED');
    const session = await callOk('posLogin', state.device.token, { instanceId: state.instanceId, staffId, pin: '2468' });
    assert.equal(session.role, 'cashier');
    assert.equal(session.name, 'Luis');

    assert.equal(
      await setDoc(
        `instances/${state.instanceId}/products/mofongo`,
        { name: 'Mofongo', priceCents: 45000, trackStock: true, stockMilli: 10000 },
        state.owner.token,
      ),
      200,
    );
    const sale = {
      number: 1,
      status: 'completed',
      totalCents: 90000,
      taxCents: 13729,
      tipCents: 0,
      changeCents: 10000,
      createdAt: new Date(),
      staffId,
      payments: [{ method: 'cash', amountCents: 100000 }],
      lines: [{ productId: 'mofongo', quantityMilli: 2000, trackStock: true }],
    };
    assert.equal(await setDoc(`instances/${state.instanceId}/sales/venta1`, sale, state.device.token), 200);

    const product = await eventually(async () => {
      const current = await getDoc(`instances/${state.instanceId}/products/mofongo`);
      return current?.stockMilli === 8000 ? current : null;
    });
    assert.ok(product, 'la venta debió descontar 2 platos del inventario');

    const day = new Date(Date.now() - 4 * 3_600_000).toISOString().slice(0, 10);
    const summary = await getDoc(`instances/${state.instanceId}/days/${day}`);
    assert.equal(summary.sales.count, 1);
    assert.equal(summary.sales.totalCents, 90000);
    assert.equal(summary.payments.cash, 90000, 'al efectivo se le resta el vuelto');
  });

  it('al salir el empleado la caja se bloquea, y el dueño la puede revocar', async () => {
    await callOk('posLogout', state.device.token, { instanceId: state.instanceId });
    const afterLogout = await setDoc(
      `instances/${state.instanceId}/sales/despues`,
      { status: 'completed', totalCents: 100 },
      state.device.token,
    );
    assert.equal(afterLogout, 403);

    await callOk('revokeDevice', state.owner.token, { instanceId: state.instanceId, deviceUid: state.device.uid });
    const device = await getDoc(`instances/${state.instanceId}/devices/${state.device.uid}`);
    assert.equal(device.status, 'revoked');
    assert.equal(await getDoc(`instances/${state.instanceId}/members/${state.device.uid}`), null);
    assert.equal((await getDoc(`accounts/${state.accountId}`)).usage.devices, 0);

    const readAfter = await getDoc(`instances/${state.instanceId}/products/mofongo`, state.device.token);
    assert.ok(readAfter?.denied, 'una caja revocada ya no ve el negocio');
  });

  it('el plan limita cuántas cajas se instalan', async () => {
    for (let i = 0; i < 3; i++) {
      const { code } = await callOk('createDeviceCode', state.owner.token, {
        instanceId: state.instanceId,
        name: `Caja ${i + 2}`,
      });
      await callOk('enrollDevice', (await signUp(null)).token, { code, platform: 'android' });
    }
    const extra = await call('createDeviceCode', state.owner.token, {
      instanceId: state.instanceId,
      name: 'Caja de más',
    });
    assert.equal(extra.error?.status, 'FAILED_PRECONDITION');
    assert.match(extra.error.message, /3 cajas/);
  });

  it('alguien de fuera no administra cajas ni empleados', async () => {
    const stranger = await signUp(`extrano-${Date.now()}@example.com`);
    const code = await call('createDeviceCode', stranger.token, { instanceId: state.instanceId, name: 'Intrusa' });
    assert.equal(code.error?.status, 'PERMISSION_DENIED');
    const staff = await call('saveStaff', stranger.token, {
      instanceId: state.instanceId,
      name: 'Intruso',
      role: 'owner',
      pin: '0000',
    });
    assert.equal(staff.error?.status, 'PERMISSION_DENIED');
  });
});
