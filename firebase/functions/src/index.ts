// VOXON · Cloud Functions.
//
// Aquí vive lo que la app no puede decidir sola:
//   - crear cuentas e instancias respetando los topes del plan,
//   - llevar el uso (cuántas instancias y usuarios hay),
//   - armar el resumen de cada día a partir de las ventas.
//
// El cobro con Stripe entra en el siguiente paso.
import { setGlobalOptions } from "firebase-functions/v2";
import { onDocumentCreated, onDocumentDeleted, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

import { DATABASE, db } from "./firestore";
import { limitsFor, modeConfig, plans, Tier, withinLimit } from "./plans";

setGlobalOptions({ region: "us-central1", maxInstances: 10 });

// Cobro con Stripe.
export * from "./billing";

const INSTANCE_ROLES = ["owner", "manager", "cashier", "waiter", "kitchen"] as const;

/** Día local de República Dominicana (UTC-4), como "2026-09-12". */
function localDay(moment: Date): string {
  return new Date(moment.getTime() - 4 * 3_600_000).toISOString().slice(0, 10);
}

function requireUid(auth: { uid: string } | undefined): string {
  if (!auth?.uid) {
    throw new HttpsError("unauthenticated", "Entra con tu cuenta primero");
  }
  return auth.uid;
}

function cleanName(value: unknown, field: string): string {
  const name = typeof value === "string" ? value.trim() : "";
  if (name.length < 1 || name.length > 80) {
    throw new HttpsError("invalid-argument", `Escribe ${field} (hasta 80 caracteres)`);
  }
  return name;
}

function requireMode(value: unknown): string {
  const mode = typeof value === "string" ? value : "";
  if (!modeConfig(mode)) {
    throw new HttpsError("invalid-argument", "Elige un modo de negocio válido");
  }
  return mode;
}

/** Datos iniciales de una instancia según su modo (ITBIS incluido, propina legal...). */
function instanceDefaults(accountId: string, name: string, mode: string) {
  const config = modeConfig(mode)!;
  return {
    accountId,
    name,
    mode,
    active: true,
    createdAt: FieldValue.serverTimestamp(),
    fiscal: { rnc: null, priceMode: config.priceMode, legalTip: config.legalTip },
  };
}

// --- Cuentas e instancias ----------------------------------------------------

/** Primer paso del cliente: su cuenta con prueba gratis y su primer negocio. */
// Las funciones que llama la app son públicas para Google; la sesión la revisa el código.
export const createAccount = onCall({ invoker: "public" }, async (request) => {
  const uid = requireUid(request.auth);
  const accountName = cleanName(request.data?.accountName, "el nombre de tu cuenta");
  const instanceName = cleanName(request.data?.instanceName, "el nombre de tu negocio");
  const mode = requireMode(request.data?.mode);

  const tier: Tier = "v45";
  const accountRef = db.collection("accounts").doc();
  const instanceRef = db.collection("instances").doc();
  const trialEndsAt = Timestamp.fromMillis(Date.now() + plans.trialDays * 86_400_000);

  const batch = db.batch();
  batch.set(accountRef, {
    name: accountName,
    ownerUid: uid,
    createdAt: FieldValue.serverTimestamp(),
    plan: { tier, status: "trial", source: "trial", trialEndsAt, currentPeriodEnd: trialEndsAt },
    limits: limitsFor(tier),
    // A los usuarios, dueño incluido, los cuenta onMemberAdded.
    usage: { instances: 1, users: 0 },
  });
  batch.set(accountRef.collection("members").doc(uid), {
    role: "owner",
    createdAt: FieldValue.serverTimestamp(),
  });
  batch.set(instanceRef, instanceDefaults(accountRef.id, instanceName, mode));
  batch.set(instanceRef.collection("members").doc(uid), {
    role: "owner",
    createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();

  return { accountId: accountRef.id, instanceId: instanceRef.id };
});

/** Un negocio más dentro de la cuenta, si el plan lo permite. */
export const createInstance = onCall({ invoker: "public" }, async (request) => {
  const uid = requireUid(request.auth);
  const accountId = typeof request.data?.accountId === "string" ? request.data.accountId : "";
  const name = cleanName(request.data?.name, "el nombre del negocio");
  const mode = requireMode(request.data?.mode);

  const accountRef = db.doc(`accounts/${accountId}`);
  const member = await accountRef.collection("members").doc(uid).get();
  if (!member.exists || !["owner", "admin"].includes(member.get("role"))) {
    throw new HttpsError("permission-denied", "Solo el dueño o un administrador de la cuenta abren negocios");
  }

  const instanceRef = db.collection("instances").doc();
  await db.runTransaction(async (transaction) => {
    const account = await transaction.get(accountRef);
    if (!account.exists) {
      throw new HttpsError("not-found", "La cuenta no existe");
    }
    const limits = account.get("limits") ?? limitsFor(account.get("plan.tier") as Tier);
    const used = (account.get("usage.instances") ?? 0) + 1;
    if (!withinLimit(used, limits.instances)) {
      throw new HttpsError(
        "failed-precondition",
        `Tu plan permite ${limits.instances} negocio(s). Sube de plan para abrir otro.`,
      );
    }
    transaction.set(instanceRef, instanceDefaults(accountId, name, mode));
    transaction.set(instanceRef.collection("members").doc(uid), {
      role: "owner",
      createdAt: FieldValue.serverTimestamp(),
    });
    transaction.update(accountRef, { "usage.instances": FieldValue.increment(1) });
  });

  return { instanceId: instanceRef.id };
});

// --- Uso de la cuenta --------------------------------------------------------

/**
 * Una persona cuenta como un solo usuario aunque trabaje en varias instancias de la
 * cuenta: accounts/{cuenta}/people/{uid} guarda en cuántas está, y usage.users solo
 * cambia cuando pasa de 0 a 1 o de 1 a 0.
 */
async function changeMembership(instanceId: string, uid: string, delta: number): Promise<void> {
  const instance = await db.doc(`instances/${instanceId}`).get();
  const accountId = instance.get("accountId");
  if (typeof accountId !== "string") {
    return;
  }
  const accountRef = db.doc(`accounts/${accountId}`);
  const personRef = accountRef.collection("people").doc(uid);
  await db.runTransaction(async (transaction) => {
    const person = await transaction.get(personRef);
    const before = person.exists ? Number(person.get("memberships") ?? 0) : 0;
    const after = Math.max(0, before + delta);
    if (after === 0) {
      transaction.delete(personRef);
    } else {
      transaction.set(personRef, { memberships: after }, { merge: true });
    }
    if (before === 0 && after > 0) {
      transaction.update(accountRef, { "usage.users": FieldValue.increment(1) });
    } else if (before > 0 && after === 0) {
      transaction.update(accountRef, { "usage.users": FieldValue.increment(-1) });
    }
  });
}

export const onMemberAdded = onDocumentCreated(
  { document: "instances/{instanceId}/members/{uid}", database: DATABASE },
  (event) => changeMembership(event.params.instanceId, event.params.uid, 1),
);

export const onMemberRemoved = onDocumentDeleted(
  { document: "instances/{instanceId}/members/{uid}", database: DATABASE },
  (event) => changeMembership(event.params.instanceId, event.params.uid, -1),
);

// --- Resumen del día ---------------------------------------------------------

interface SaleTotals {
  count: number;
  totalCents: number;
  taxCents: number;
  tipCents: number;
  discountCents: number;
}

function totalsOf(sale: FirebaseFirestore.DocumentData, sign: number): SaleTotals {
  return {
    count: sign,
    totalCents: sign * Number(sale.totalCents ?? 0),
    taxCents: sign * Number(sale.taxCents ?? 0),
    tipCents: sign * Number(sale.tipCents ?? 0),
    discountCents: sign * Number(sale.discountCents ?? 0),
  };
}

/** Cobros netos por método: al efectivo se le resta el vuelto. */
function paymentsOf(sale: FirebaseFirestore.DocumentData, sign: number): Record<string, number> {
  const payments: Record<string, number> = {};
  const lines: FirebaseFirestore.DocumentData[] = Array.isArray(sale.payments) ? sale.payments : [];
  for (const line of lines) {
    const method = typeof line.method === "string" ? line.method : "cash";
    const change = method === "cash" ? Number(sale.changeCents ?? 0) : 0;
    payments[method] = (payments[method] ?? 0) + sign * (Number(line.amountCents ?? 0) - change);
  }
  return payments;
}

/** Suma (o resta, al anular) una venta en el documento del día. */
async function applySale(
  instanceId: string,
  sale: FirebaseFirestore.DocumentData,
  sign: number,
): Promise<void> {
  const createdAt: Date = sale.createdAt?.toDate?.() ?? new Date();
  const day = localDay(createdAt);
  const totals = totalsOf(sale, sign);

  const update: FirebaseFirestore.DocumentData = {
    day,
    updatedAt: FieldValue.serverTimestamp(),
    sales: {
      count: FieldValue.increment(totals.count),
      totalCents: FieldValue.increment(totals.totalCents),
      taxCents: FieldValue.increment(totals.taxCents),
      tipCents: FieldValue.increment(totals.tipCents),
      discountCents: FieldValue.increment(totals.discountCents),
    },
    payments: Object.fromEntries(
      Object.entries(paymentsOf(sale, sign)).map(([method, amount]) => [method, FieldValue.increment(amount)]),
    ),
  };
  if (sign < 0) {
    update.voided = {
      count: FieldValue.increment(1),
      totalCents: FieldValue.increment(Number(sale.totalCents ?? 0)),
    };
  }
  await db.doc(`instances/${instanceId}/days/${day}`).set(update, { merge: true });
}

export const onSaleCreated = onDocumentCreated(
  { document: "instances/{instanceId}/sales/{saleId}", database: DATABASE },
  async (event) => {
    const sale = event.data?.data();
    if (!sale || sale.status !== "completed") {
      return;
    }
    await applySale(event.params.instanceId, sale, 1);
  },
);

export const onSaleVoided = onDocumentUpdated(
  { document: "instances/{instanceId}/sales/{saleId}", database: DATABASE },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.status !== "completed" || after.status !== "voided") {
      return;
    }
    await applySale(event.params.instanceId, after, -1);
  },
);

// --- Invitaciones ------------------------------------------------------------

/** Deja la invitación lista para que el empleado entre con el código. */
export const createInvite = onCall({ invoker: "public" }, async (request) => {
  const uid = requireUid(request.auth);
  const instanceId = typeof request.data?.instanceId === "string" ? request.data.instanceId : "";
  const role = typeof request.data?.role === "string" ? request.data.role : "";
  if (!(INSTANCE_ROLES as readonly string[]).includes(role)) {
    throw new HttpsError("invalid-argument", "Elige un puesto válido");
  }

  const member = await db.doc(`instances/${instanceId}/members/${uid}`).get();
  if (!member.exists || !["owner", "manager"].includes(member.get("role"))) {
    throw new HttpsError("permission-denied", "Solo el dueño o un gerente invitan empleados");
  }

  const account = await db.doc(`instances/${instanceId}`).get();
  const accountRef = db.doc(`accounts/${account.get("accountId")}`);
  const accountSnapshot = await accountRef.get();
  const limits = accountSnapshot.get("limits");
  const used = (accountSnapshot.get("usage.users") ?? 0) + 1;
  if (limits && !withinLimit(used, limits.users)) {
    throw new HttpsError(
      "failed-precondition",
      `Tu plan permite ${limits.users} usuarios. Sube de plan para agregar más.`,
    );
  }

  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < 8; i++) {
    code += alphabet.charAt(Math.floor(Math.random() * alphabet.length));
  }
  await db.doc(`invites/${code}`).set({
    instanceId,
    role,
    createdBy: uid,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromMillis(Date.now() + 7 * 86_400_000),
  });
  return { code };
});
