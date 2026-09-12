// Reglas multi-tenant de VOXON, contra el emulador.
//   npm test   (arranca el emulador y corre este archivo)
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { collection, deleteDoc, doc, getDoc, getDocs, setDoc, Timestamp, updateDoc } from 'firebase/firestore';

const ACCOUNT = 'cuenta1';
const INSTANCE = 'negocio1';
const OTHER_INSTANCE = 'negocio2';

let env;

const inDays = (days) => Timestamp.fromMillis(Date.now() + days * 86_400_000);

const db = (uid) =>
  uid === null ? env.unauthenticatedContext().firestore() : env.authenticatedContext(uid).firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-voxon',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});

after(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const admin = context.firestore();
    await setDoc(doc(admin, 'accounts', ACCOUNT), {
      name: 'Grupo Ana',
      ownerUid: 'ana',
      plan: { tier: 'v90', status: 'active' },
      limits: { instances: 2, users: 5, products: 5000, devices: 3 },
      usage: { instances: 1, users: 3 },
      billing: { stripeCustomerId: 'cus_123' },
    });
    await setDoc(doc(admin, 'accounts', ACCOUNT, 'members', 'ana'), { role: 'owner' });
    await setDoc(doc(admin, 'instances', INSTANCE), {
      accountId: ACCOUNT,
      name: 'Colmado La Esquina',
      mode: 'colmado',
      active: true,
    });
    await setDoc(doc(admin, 'instances', OTHER_INSTANCE), {
      accountId: 'cuenta2',
      name: 'Ajeno',
      mode: 'store',
      active: true,
    });
    for (const [uid, role] of [
      ['ana', 'owner'],
      ['marta', 'manager'],
      ['luis', 'cashier'],
      ['pedro', 'waiter'],
      ['coci', 'kitchen'],
    ]) {
      await setDoc(doc(admin, 'instances', INSTANCE, 'members', uid), { role });
    }
    await setDoc(doc(admin, 'instances', INSTANCE, 'sales', 'venta1'), {
      number: 1,
      status: 'completed',
      totalCents: 17700,
      cashierUid: 'luis',
    });
    await setDoc(doc(admin, 'instances', INSTANCE, 'cashSessions', 'caja1'), {
      openedBy: 'luis',
      closedAt: null,
      openingFloatCents: 100000,
    });
    await setDoc(doc(admin, 'instances', INSTANCE, 'orders', 'orden1'), {
      number: 1,
      status: 'open',
      items: [{ productId: 'p1', status: 'sent' }],
    });
    await setDoc(doc(admin, 'invites', 'INVITA01'), {
      instanceId: INSTANCE,
      role: 'cashier',
      expiresAt: inDays(7),
    });
    await setDoc(doc(admin, 'invites', 'VENCIDA1'), {
      instanceId: INSTANCE,
      role: 'cashier',
      expiresAt: inDays(-1),
    });
  });
});

describe('separación entre negocios', () => {
  it('un empleado solo ve su instancia', async () => {
    await assertSucceeds(getDoc(doc(db('luis'), 'instances', INSTANCE)));
    await assertSucceeds(getDocs(collection(db('luis'), 'instances', INSTANCE, 'products')));

    await assertFails(getDoc(doc(db('luis'), 'instances', OTHER_INSTANCE)));
    await assertFails(getDocs(collection(db('luis'), 'instances', OTHER_INSTANCE, 'sales')));
    await assertFails(getDoc(doc(db(null), 'instances', INSTANCE)));
  });

  it('nadie escribe en una instancia ajena', async () => {
    await assertFails(
      setDoc(doc(db('ana'), 'instances', OTHER_INSTANCE, 'products', 'p1'), { name: 'Intruso' }),
    );
  });
});

describe('roles dentro de la instancia', () => {
  it('el catálogo lo cambian dueño y gerente', async () => {
    await assertSucceeds(
      setDoc(doc(db('marta'), 'instances', INSTANCE, 'products', 'p1'), { name: 'Refresco', priceCents: 5900 }),
    );
    await assertFails(
      setDoc(doc(db('luis'), 'instances', INSTANCE, 'products', 'p2'), { name: 'Cerveza', priceCents: 9900 }),
    );
    await assertSucceeds(getDoc(doc(db('luis'), 'instances', INSTANCE, 'products', 'p1')));
  });

  it('el cajero vende pero no anula', async () => {
    await assertSucceeds(
      setDoc(doc(db('luis'), 'instances', INSTANCE, 'sales', 'venta2'), {
        number: 2,
        status: 'completed',
        totalCents: 5900,
        cashierUid: 'luis',
      }),
    );
    await assertFails(
      updateDoc(doc(db('luis'), 'instances', INSTANCE, 'sales', 'venta1'), {
        status: 'voided',
        voidedAt: Timestamp.now(),
        voidedBy: 'luis',
        voidReason: 'Error',
      }),
    );
    await assertFails(
      setDoc(doc(db('pedro'), 'instances', INSTANCE, 'sales', 'venta3'), { number: 3, status: 'completed' }),
    );
  });

  it('cocina solo mueve el estado de la comanda', async () => {
    await assertSucceeds(
      updateDoc(doc(db('coci'), 'instances', INSTANCE, 'orders', 'orden1'), {
        items: [{ productId: 'p1', status: 'ready' }],
        updatedAt: Timestamp.now(),
      }),
    );
    await assertFails(
      updateDoc(doc(db('coci'), 'instances', INSTANCE, 'orders', 'orden1'), { status: 'closed' }),
    );
    await assertSucceeds(
      updateDoc(doc(db('pedro'), 'instances', INSTANCE, 'orders', 'orden1'), { status: 'closed' }),
    );
  });
});

describe('una venta cobrada no se toca', () => {
  it('solo se anula, y nunca se borra', async () => {
    await assertSucceeds(
      updateDoc(doc(db('ana'), 'instances', INSTANCE, 'sales', 'venta1'), {
        status: 'voided',
        voidedAt: Timestamp.now(),
        voidedBy: 'ana',
        voidReason: 'Cobro duplicado',
      }),
    );
    await assertFails(
      updateDoc(doc(db('ana'), 'instances', INSTANCE, 'sales', 'venta1'), { totalCents: 1 }),
    );
    await assertFails(deleteDoc(doc(db('ana'), 'instances', INSTANCE, 'sales', 'venta1')));
  });

  it('la caja cerrada queda como está', async () => {
    await assertSucceeds(
      updateDoc(doc(db('luis'), 'instances', INSTANCE, 'cashSessions', 'caja1'), {
        countedCashCents: 111800,
        closedAt: Timestamp.now(),
      }),
    );
    await assertFails(
      updateDoc(doc(db('luis'), 'instances', INSTANCE, 'cashSessions', 'caja1'), { countedCashCents: 0 }),
    );
  });
});

describe('el dinero lo maneja el servidor', () => {
  it('nadie cambia su plan, sus topes ni su facturación', async () => {
    await assertFails(
      updateDoc(doc(db('ana'), 'accounts', ACCOUNT), { plan: { tier: 'v360', status: 'active' } }),
    );
    await assertFails(updateDoc(doc(db('ana'), 'accounts', ACCOUNT), { limits: { instances: 99 } }));
    await assertFails(updateDoc(doc(db('ana'), 'accounts', ACCOUNT), { usage: { instances: 0 } }));
    await assertSucceeds(updateDoc(doc(db('ana'), 'accounts', ACCOUNT), { name: 'Grupo Ana SRL' }));
  });

  it('las cuentas las crea el servidor, no el cliente', async () => {
    await assertFails(
      setDoc(doc(db('nueva'), 'accounts', 'cuenta3'), {
        name: 'Bar La Última',
        ownerUid: 'nueva',
        plan: { tier: 'v45', status: 'trial' },
      }),
    );
  });

  it('el resumen del día lo escribe el servidor', async () => {
    await assertFails(
      setDoc(doc(db('ana'), 'instances', INSTANCE, 'days', '2026-09-11'), { totalCents: 999 }),
    );
    await assertSucceeds(getDoc(doc(db('ana'), 'instances', INSTANCE, 'days', '2026-09-11')));
  });
});

describe('instancias e invitaciones', () => {
  it('las instancias las crea el servidor, para respetar el tope del plan', async () => {
    await assertFails(
      setDoc(doc(db('ana'), 'instances', 'negocio3'), {
        accountId: ACCOUNT,
        name: 'Sucursal 2',
        mode: 'restaurant',
        active: true,
      }),
    );
    // Lo que ya existe sí lo administra el dueño.
    await assertSucceeds(
      updateDoc(doc(db('ana'), 'instances', INSTANCE), { name: 'Colmado La Esquina II' }),
    );
    await assertFails(
      updateDoc(doc(db('luis'), 'instances', INSTANCE), { name: 'Del cajero' }),
    );
  });

  it('un empleado entra con una invitación vigente', async () => {
    await assertSucceeds(
      setDoc(doc(db('nuevo'), 'instances', INSTANCE, 'members', 'nuevo'), {
        role: 'cashier',
        inviteCode: 'INVITA01',
      }),
    );
    await assertFails(
      setDoc(doc(db('otro'), 'instances', INSTANCE, 'members', 'otro'), {
        role: 'cashier',
        inviteCode: 'VENCIDA1',
      }),
    );
    // La invitación no sirve para darse un rol mayor.
    await assertFails(
      setDoc(doc(db('vivo'), 'instances', INSTANCE, 'members', 'vivo'), {
        role: 'owner',
        inviteCode: 'INVITA01',
      }),
    );
  });

  it('las invitaciones las crea quien manda y duran poco', async () => {
    await assertSucceeds(
      setDoc(doc(db('marta'), 'invites', 'NUEVA001'), {
        instanceId: INSTANCE,
        role: 'waiter',
        expiresAt: inDays(3),
      }),
    );
    await assertFails(
      setDoc(doc(db('marta'), 'invites', 'LARGA001'), {
        instanceId: INSTANCE,
        role: 'waiter',
        expiresAt: inDays(30),
      }),
    );
    await assertFails(
      setDoc(doc(db('luis'), 'invites', 'DELCAJERO'), {
        instanceId: INSTANCE,
        role: 'owner',
        expiresAt: inDays(1),
      }),
    );
  });
});
