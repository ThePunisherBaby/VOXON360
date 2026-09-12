// VOXON · Cloud Functions.
//
// Lo que las apps no pueden decidir solas:
//   - crear cuentas e instancias respetando los topes del plan,
//   - vincular cajas y validar el PIN de los empleados (devices.ts),
//   - llevar el uso de cada cuenta,
//   - armar el resumen del día y mover el inventario con cada venta,
//   - cobrar con Stripe (billing.ts).
import { logger, setGlobalOptions } from "firebase-functions/v2";
import { onDocumentCreated, onDocumentDeleted, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

import { cleanName, requireUid, stringParam } from "./common";
import { DATABASE, db } from "./firestore";
import { limitsFor, modeConfig, plans, withinLimit } from "./plans";
import { randomCode } from "./security";

setGlobalOptions({ region: "us-central1", maxInstances: 10 });

export * from "./billing";
export * from "./devices";
export * from "./pairing";

const INSTANCE_ROLES = ["owner", "manager", "cashier", "waiter", "kitchen"];

/** Día local de República Dominicana (UTC-4), como "2026-09-12". */
function localDay(moment: Date): string {
  return new Date(moment.getTime() - 4 * 3_600_000).toISOString().slice(0, 10);
}

/** Modo que se puede elegir hoy: los "planned" todavía no están listos. */
function requireMode(value: unknown): string {
  const mode = stringParam(value);
  const config = modeConfig(mode);
  if (!config) {
    throw new HttpsError("invalid-argument", "Elige un modo de negocio válido");
  }
  if (config.status === "planned") {
    throw new HttpsError("failed-precondition", `El modo ${config.name} estará disponible pronto`);
  }
  return mode;
}

type Write = (ref: FirebaseFirestore.DocumentReference, data: FirebaseFirestore.DocumentData) => void;

/** Instancia nueva según su modo: módulos, reglas fiscales, marca, categorías y estaciones. */
function writeInstance(
  write: Write,
  instanceRef: FirebaseFirestore.DocumentReference,
  accountId: string,
  name: string,
  mode: string,
  ownerUid: string,
): void {
  const config = modeConfig(mode)!;
  const now = FieldValue.serverTimestamp();
  write(instanceRef, {
    accountId,
    name,
    mode,
    active: true,
    createdAt: now,
    deviceCount: 0,
    modules: config.modules,
    fiscal: { rnc: null, priceMode: config.priceMode, legalTip: config.legalTip },
  });
  write(instanceRef.collection("members").doc(ownerUid), { role: "owner", kind: "user", createdAt: now });
  // Índice para que VOXON 360 muestre el negocio apenas se crea (los disparadores lo mantienen después).
  write(db.doc(`users/${ownerUid}/instances/${instanceRef.id}`), {
    accountId,
    name,
    mode,
    role: "owner",
    updatedAt: now,
  });
  write(instanceRef.collection("settings").doc("branding"), {
    displayName: name,
    primaryColor: config.color,
    logoDataUrl: null,
    receiptFooter: "¡Gracias por su compra!",
  });
  config.categories.forEach((category, index) =>
    write(instanceRef.collection("categories").doc(), { name: category, sortOrder: index, active: true }),
  );
  (config.stations ?? []).forEach((station, index) =>
    write(instanceRef.collection("stations").doc(), { name: station, sortOrder: index }),
  );
}

// --- Cuentas e instancias ----------------------------------------------------

/** Primer paso del cliente: su cuenta con prueba gratis y su primer negocio. */
export const createAccount = onCall({ invoker: "public" }, async (request) => {
  const uid = requireUid(request.auth);
  const accountName = cleanName(request.data?.accountName, "el nombre de tu cuenta");
  const instanceName = cleanName(request.data?.instanceName, "el nombre de tu negocio");
  const mode = requireMode(request.data?.mode);

  const tier = plans.trialTier;
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
    // Las personas con cuenta las cuenta onMemberAdded; los empleados, saveStaff; las cajas, enrollDevice.
    usage: { instances: 1, users: 0, staff: 0, devices: 0 },
  });
  batch.set(accountRef.collection("members").doc(uid), {
    role: "owner",
    createdAt: FieldValue.serverTimestamp(),
  });
  writeInstance((ref, data) => batch.set(ref, data), instanceRef, accountRef.id, instanceName, mode, uid);
  await batch.commit();

  return { accountId: accountRef.id, instanceId: instanceRef.id };
});

/** Un negocio más dentro de la cuenta, si el plan lo permite. */
export const createInstance = onCall({ invoker: "public" }, async (request) => {
  const uid = requireUid(request.auth);
  const accountId = stringParam(request.data?.accountId);
  const name = cleanName(request.data?.name, "el nombre del negocio");
  const mode = requireMode(request.data?.mode);
  if (!accountId) {
    throw new HttpsError("invalid-argument", "Falta la cuenta");
  }

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
    const limits = account.get("limits") ?? limitsFor(account.get("plan.tier"));
    const used = Number(account.get("usage.instances") ?? 0) + 1;
    if (!withinLimit(used, limits.instances)) {
      throw new HttpsError(
        "failed-precondition",
        `Tu plan permite ${limits.instances} negocio(s). Sube de plan para abrir otro.`,
      );
    }
    writeInstance((ref, data) => transaction.set(ref, data), instanceRef, accountId, name, mode, uid);
    transaction.update(accountRef, { "usage.instances": FieldValue.increment(1) });
  });

  return { instanceId: instanceRef.id };
});

// --- Uso de la cuenta --------------------------------------------------------

/**
 * Una persona cuenta como un solo usuario aunque trabaje en varias instancias de la
 * cuenta: accounts/{cuenta}/people/{uid} guarda en cuántas está, y usage.users solo
 * cambia cuando pasa de 0 a 1 o de 1 a 0. Las cajas no son personas.
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

/** users/{uid}/instances: los negocios donde trabaja cada persona, para que VOXON 360 los liste. */
async function writeUserIndex(instanceId: string, uid: string, role: string): Promise<void> {
  const instance = await db.doc(`instances/${instanceId}`).get();
  if (!instance.exists) {
    return;
  }
  await db.doc(`users/${uid}/instances/${instanceId}`).set({
    accountId: instance.get("accountId"),
    name: instance.get("name"),
    mode: instance.get("mode"),
    role,
    updatedAt: FieldValue.serverTimestamp(),
  });
}

export const onMemberAdded = onDocumentCreated(
  { document: "instances/{instanceId}/members/{uid}", database: DATABASE },
  async (event) => {
    const member = event.data?.data();
    if (!member || member.kind === "device") {
      return;
    }
    await Promise.all([
      changeMembership(event.params.instanceId, event.params.uid, 1),
      writeUserIndex(event.params.instanceId, event.params.uid, member.role),
    ]);
  },
);

/** Si a una persona le cambian el puesto, se refleja en su lista de negocios. */
export const onMemberUpdated = onDocumentUpdated(
  { document: "instances/{instanceId}/members/{uid}", database: DATABASE },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || after.kind === "device" || before.role === after.role) {
      return;
    }
    await writeUserIndex(event.params.instanceId, event.params.uid, after.role);
  },
);

export const onMemberRemoved = onDocumentDeleted(
  { document: "instances/{instanceId}/members/{uid}", database: DATABASE },
  async (event) => {
    if (event.data?.data()?.kind === "device") {
      return;
    }
    await Promise.all([
      changeMembership(event.params.instanceId, event.params.uid, -1),
      db.doc(`users/${event.params.uid}/instances/${event.params.instanceId}`).delete(),
    ]);
  },
);

/** Si el negocio cambia de nombre, se actualiza en la lista de cada persona. */
export const onInstanceUpdated = onDocumentUpdated(
  { document: "instances/{instanceId}", database: DATABASE },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.name === after.name) {
      return;
    }
    const members = await db.collection(`instances/${event.params.instanceId}/members`).get();
    const batch = db.batch();
    for (const member of members.docs) {
      if (member.get("kind") !== "device") {
        batch.set(
          db.doc(`users/${member.id}/instances/${event.params.instanceId}`),
          { name: after.name, updatedAt: FieldValue.serverTimestamp() },
          { merge: true },
        );
      }
    }
    await batch.commit();
  },
);

// --- Resumen del día e inventario ----------------------------------------------

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

/** Suma (o resta, al anular) una venta en el día y mueve el inventario de sus productos. */
async function applySale(instanceId: string, sale: FirebaseFirestore.DocumentData, sign: number): Promise<void> {
  const createdAt: Date = sale.createdAt?.toDate?.() ?? new Date();
  const day = localDay(createdAt);

  const update: FirebaseFirestore.DocumentData = {
    day,
    updatedAt: FieldValue.serverTimestamp(),
    sales: {
      count: FieldValue.increment(sign),
      totalCents: FieldValue.increment(sign * Number(sale.totalCents ?? 0)),
      taxCents: FieldValue.increment(sign * Number(sale.taxCents ?? 0)),
      tipCents: FieldValue.increment(sign * Number(sale.tipCents ?? 0)),
      discountCents: FieldValue.increment(sign * Number(sale.discountCents ?? 0)),
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

  // Inventario: vender descuenta y anular devuelve. Una presentación (una caja de 20)
  // descuenta del producto base con su factor.
  const lines: FirebaseFirestore.DocumentData[] = Array.isArray(sale.lines) ? sale.lines : [];
  const stockMoves = lines
    .filter((line) => line.trackStock === true && typeof (line.stockProductId ?? line.productId) === "string")
    .map((line) => {
      const productId: string = line.stockProductId ?? line.productId;
      const quantity = Number(line.quantityMilli ?? 0) * Number(line.stockFactor ?? 1);
      return db
        .doc(`instances/${instanceId}/products/${productId}`)
        .update({ stockMilli: FieldValue.increment(-sign * quantity) });
    });
  const results = await Promise.allSettled(stockMoves);
  for (const result of results) {
    if (result.status === "rejected") {
      logger.warn("No se pudo mover el inventario de un producto", { instanceId, error: `${result.reason}` });
    }
  }
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

/** Invitación para que otra persona con cuenta entre a VOXON 360 en esta instancia. */
export const createInvite = onCall({ invoker: "public" }, async (request) => {
  const uid = requireUid(request.auth);
  const instanceId = stringParam(request.data?.instanceId);
  const role = stringParam(request.data?.role);
  if (!instanceId || !INSTANCE_ROLES.includes(role)) {
    throw new HttpsError("invalid-argument", "Elige el negocio y un puesto válido");
  }

  const member = await db.doc(`instances/${instanceId}/members/${uid}`).get();
  const callerRole = member.exists && member.get("kind") !== "device" ? member.get("role") : null;
  if (!["owner", "manager"].includes(callerRole)) {
    throw new HttpsError("permission-denied", "Solo el dueño o un gerente invitan personas");
  }
  if (["owner", "manager"].includes(role) && callerRole !== "owner") {
    throw new HttpsError("permission-denied", "Solo el dueño invita dueños o gerentes");
  }

  const instance = await db.doc(`instances/${instanceId}`).get();
  const account = await db.doc(`accounts/${instance.get("accountId")}`).get();
  const limits = account.get("limits");
  const used = Number(account.get("usage.users") ?? 0) + Number(account.get("usage.staff") ?? 0) + 1;
  if (limits && !withinLimit(used, limits.users)) {
    throw new HttpsError("failed-precondition", `Tu plan permite ${limits.users} usuarios. Sube de plan para agregar más.`);
  }

  const code = randomCode();
  await db.doc(`invites/${code}`).set({
    instanceId,
    role,
    createdBy: uid,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromMillis(Date.now() + 7 * 86_400_000),
  });
  return { code };
});
