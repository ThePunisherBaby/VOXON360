// Reglas de Firestore de la app del dueño, contra el emulador.
//   npm test   (arranca el emulador y corre este archivo)
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { collection, deleteDoc, doc, getDoc, getDocs, setDoc, Timestamp } from 'firebase/firestore';

const BUSINESS = 'negocio1';
const DAY = '2026-09-11';

/** Resumen de un día, como el que sube la caja principal. */
const daySummary = {
  day: DAY,
  sales: { count: 2, totalCents: 17700 },
  syncedAt: Timestamp.now(),
};

let env;

/** Minutos a partir de ahora, para el vencimiento de un código. */
const inMinutes = (minutes) => Timestamp.fromMillis(Date.now() + minutes * 60_000);

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-voxon90',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});

after(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'businesses', BUSINESS), {
      name: 'Colmado La Esquina',
      ownerUids: ['dueno'],
    });
    await setDoc(doc(db, 'businesses', BUSINESS, 'devices', 'caja'), {
      linkCode: 'ABCD2345',
      name: 'Caja principal',
    });
    await setDoc(doc(db, 'linkCodes', 'VIGENTE2'), {
      businessId: BUSINESS,
      ownerUid: 'dueno',
      expiresAt: inMinutes(10),
    });
    await setDoc(doc(db, 'linkCodes', 'VENCIDO2'), {
      businessId: BUSINESS,
      ownerUid: 'dueno',
      expiresAt: inMinutes(-10),
    });
  });
});

const caja = () => env.authenticatedContext('caja').firestore();
const dueno = () => env.authenticatedContext('dueno').firestore();
const extrano = () => env.authenticatedContext('extrano').firestore();
const sinSesion = () => env.unauthenticatedContext().firestore();

describe('la caja vinculada', () => {
  it('escribe los resúmenes de su negocio', async () => {
    await assertSucceeds(setDoc(doc(caja(), 'businesses', BUSINESS, 'days', DAY), daySummary));
    await assertSucceeds(
      setDoc(doc(caja(), 'businesses', BUSINESS, 'snapshots', 'status'), { openOrders: 0 }),
    );
    await assertSucceeds(
      setDoc(doc(caja(), 'businesses', BUSINESS, 'snapshots', 'receivables'), { totalCents: 5900 }),
    );
  });

  it('no escribe nada más del negocio', async () => {
    await assertFails(setDoc(doc(caja(), 'businesses', BUSINESS), { name: 'Otro nombre', ownerUids: ['caja'] }));
    await assertFails(setDoc(doc(caja(), 'businesses', BUSINESS, 'snapshots', 'otro'), { x: 1 }));
    await assertFails(setDoc(doc(caja(), 'businesses', BUSINESS, 'days', 'mañana'), daySummary));
  });

  it('no lee los datos del dueño', async () => {
    await assertFails(getDoc(doc(caja(), 'businesses', BUSINESS, 'days', DAY)));
  });
});

describe('una caja sin vincular', () => {
  it('no puede escribir en el negocio', async () => {
    await assertFails(setDoc(doc(extrano(), 'businesses', BUSINESS, 'days', DAY), daySummary));
    await assertFails(setDoc(doc(extrano(), 'businesses', BUSINESS, 'snapshots', 'status'), { openOrders: 9 }));
    await assertFails(setDoc(doc(sinSesion(), 'businesses', BUSINESS, 'days', DAY), daySummary));
  });

  it('se registra solo con un código vigente', async () => {
    await assertSucceeds(
      setDoc(doc(env.authenticatedContext('caja2').firestore(), 'businesses', BUSINESS, 'devices', 'caja2'), {
        linkCode: 'VIGENTE2',
        name: 'Caja principal',
      }),
    );
    await assertFails(
      setDoc(doc(env.authenticatedContext('caja3').firestore(), 'businesses', BUSINESS, 'devices', 'caja3'), {
        linkCode: 'VENCIDO2',
        name: 'Caja principal',
      }),
    );
    await assertFails(
      setDoc(doc(env.authenticatedContext('caja4').firestore(), 'businesses', BUSINESS, 'devices', 'caja4'), {
        linkCode: 'NOEXISTE',
        name: 'Caja principal',
      }),
    );
    // Tampoco puede registrar a otro equipo con su código.
    await assertFails(
      setDoc(doc(env.authenticatedContext('caja5').firestore(), 'businesses', BUSINESS, 'devices', 'caja6'), {
        linkCode: 'VIGENTE2',
        name: 'Caja principal',
      }),
    );
  });
});

describe('el dueño', () => {
  it('lee su negocio y nadie más', async () => {
    await assertSucceeds(getDoc(doc(dueno(), 'businesses', BUSINESS)));
    await assertSucceeds(getDocs(collection(dueno(), 'businesses', BUSINESS, 'days')));
    await assertSucceeds(getDoc(doc(dueno(), 'businesses', BUSINESS, 'snapshots', 'status')));

    await assertFails(getDoc(doc(extrano(), 'businesses', BUSINESS)));
    await assertFails(getDocs(collection(extrano(), 'businesses', BUSINESS, 'days')));
    await assertFails(getDoc(doc(sinSesion(), 'businesses', BUSINESS, 'days', DAY)));
  });

  it('crea su negocio con él como único dueño', async () => {
    const db = env.authenticatedContext('nuevo').firestore();
    await assertSucceeds(setDoc(doc(db, 'businesses', 'negocio2'), { name: 'Bar La Última', ownerUids: ['nuevo'] }));
    await assertFails(setDoc(doc(db, 'businesses', 'negocio3'), { name: 'Ajeno', ownerUids: ['dueno'] }));
    await assertFails(setDoc(doc(db, 'businesses', 'negocio4'), { name: '', ownerUids: ['nuevo'] }));
  });

  it('genera códigos que vencen pronto', async () => {
    await assertSucceeds(
      setDoc(doc(dueno(), 'linkCodes', 'NUEVACAJ'), {
        businessId: BUSINESS,
        ownerUid: 'dueno',
        expiresAt: inMinutes(15),
      }),
    );
    await assertFails(
      setDoc(doc(dueno(), 'linkCodes', 'LARGA234'), {
        businessId: BUSINESS,
        ownerUid: 'dueno',
        expiresAt: inMinutes(120),
      }),
    );
    await assertFails(
      setDoc(doc(dueno(), 'linkCodes', 'minuscul'), {
        businessId: BUSINESS,
        ownerUid: 'dueno',
        expiresAt: inMinutes(15),
      }),
    );
    // Nadie genera códigos para un negocio ajeno.
    await assertFails(
      setDoc(doc(extrano(), 'linkCodes', 'AJENA234'), {
        businessId: BUSINESS,
        ownerUid: 'extrano',
        expiresAt: inMinutes(15),
      }),
    );
  });

  it('quita una caja para revocarla', async () => {
    await assertSucceeds(deleteDoc(doc(dueno(), 'businesses', BUSINESS, 'devices', 'caja')));
    await assertFails(deleteDoc(doc(extrano(), 'businesses', BUSINESS, 'devices', 'caja')));
  });
});

describe('los códigos de vínculo', () => {
  it('se leen mientras estén vigentes y nunca se listan', async () => {
    await assertSucceeds(getDoc(doc(caja(), 'linkCodes', 'VIGENTE2')));
    await assertFails(getDoc(doc(caja(), 'linkCodes', 'VENCIDO2')));
    await assertFails(getDoc(doc(sinSesion(), 'linkCodes', 'VIGENTE2')));
    await assertFails(getDocs(collection(caja(), 'linkCodes')));
  });
});
