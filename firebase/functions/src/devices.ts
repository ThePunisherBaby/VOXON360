// Cajas (VOXON POS) y empleados con PIN.
//
// Una caja se vincula con un código que genera VOXON 360. La caja entra a Firebase como usuario
// anónimo y queda como miembro "device" de la instancia con rol "locked": ve los datos, pero no
// vende hasta que un empleado entra con su PIN. El PIN se valida aquí, contra un hash que ninguna
// app puede leer, y el rol del empleado pasa a la sesión de la caja hasta que sale.
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { cleanName, requireUid, stringParam } from "./common";
import { db } from "./firestore";
import { hasFeature, isTier, Limits, limitsFor, Tier, withinLimit } from "./plans";
import { hashPin, isValidPin, PinHash, randomCode, verifyPin } from "./security";

const STAFF_ROLES = ["owner", "manager", "cashier", "waiter", "kitchen"];
const CODE_LIFETIME_MS = 24 * 3_600_000;
const MAX_PIN_FAILURES = 5;
const PIN_LOCK_MS = 30_000;
const DEVICE_CODE = /^[A-HJ-NP-Z2-9]{8}$/;

type Snapshot = FirebaseFirestore.DocumentSnapshot;

interface InstanceAdmin {
  instance: Snapshot;
  /** Dueño de la instancia o dueño/administrador de la cuenta: puede dar puestos altos. */
  isOwner: boolean;
}

/** Dueño o gerente de la instancia (con su cuenta, no desde una caja) o administrador de la cuenta. */
async function requireInstanceAdmin(instanceId: string, uid: string): Promise<InstanceAdmin> {
  if (!instanceId) {
    throw new HttpsError("invalid-argument", "Falta el negocio");
  }
  const instance = await db.doc(`instances/${instanceId}`).get();
  if (!instance.exists) {
    throw new HttpsError("not-found", "El negocio no existe");
  }
  const [member, accountMember] = await Promise.all([
    db.doc(`instances/${instanceId}/members/${uid}`).get(),
    db.doc(`accounts/${instance.get("accountId")}/members/${uid}`).get(),
  ]);
  const personRole = member.exists && member.get("kind") !== "device" ? member.get("role") : null;
  const accountAdmin = accountMember.exists && ["owner", "admin"].includes(accountMember.get("role"));
  if (!accountAdmin && !["owner", "manager"].includes(personRole)) {
    throw new HttpsError("permission-denied", "Solo el dueño o un gerente administran las cajas y los empleados");
  }
  return { instance, isOwner: accountAdmin || personRole === "owner" };
}

function planOf(account: Snapshot): { tier: Tier; limits: Limits } {
  const tier = account.get("plan.tier");
  if (!isTier(tier)) {
    throw new HttpsError("failed-precondition", "La cuenta no tiene un plan válido");
  }
  return { tier, limits: account.get("limits") ?? limitsFor(tier) };
}

/** Revisa que el plan tenga cajas y que quepa una más. */
function requireDeviceRoom(account: Snapshot): void {
  const { tier, limits } = planOf(account);
  if (!hasFeature(tier, "posDevices")) {
    throw new HttpsError(
      "failed-precondition",
      "Las cajas con VOXON POS vienen desde el plan 90. En el plan 45 se vende desde VOXON 360.",
    );
  }
  const used = Number(account.get("usage.devices") ?? 0) + 1;
  if (!withinLimit(used, limits.devices)) {
    throw new HttpsError("failed-precondition", `Tu plan permite ${limits.devices} cajas. Sube de plan o desactiva una.`);
  }
}

// --- Cajas -------------------------------------------------------------------

/** VOXON 360 pide un código para instalar una caja nueva. */
export const createDeviceCode = onCall({ invoker: "public" }, async (request) => {
  const uid = requireUid(request.auth);
  const instanceId = stringParam(request.data?.instanceId);
  const name = cleanName(request.data?.name || "Caja", "el nombre de la caja", 40);
  const { instance } = await requireInstanceAdmin(instanceId, uid);
  const accountId = instance.get("accountId");
  requireDeviceRoom(await db.doc(`accounts/${accountId}`).get());

  const code = randomCode();
  const expiresAt = Timestamp.fromMillis(Date.now() + CODE_LIFETIME_MS);
  await db.doc(`deviceCodes/${code}`).set({
    instanceId,
    accountId,
    name,
    createdBy: uid,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt,
    usedAt: null,
  });
  return { code, expiresAt: expiresAt.toDate().toISOString(), instanceName: instance.get("name"), deviceName: name };
});

/** VOXON POS canjea el código y queda vinculado a la instancia. */
export const enrollDevice = onCall({ invoker: "public" }, async (request) => {
  const uid = requireUid(request.auth);
  const code = stringParam(request.data?.code).replace(/[\s-]/g, "").toUpperCase();
  const platform = stringParam(request.data?.platform).slice(0, 20) || "desconocida";
  if (!DEVICE_CODE.test(code)) {
    throw new HttpsError("invalid-argument", "El código tiene 8 letras y números, como aparece en VOXON 360");
  }

  const codeRef = db.doc(`deviceCodes/${code}`);
  return db.runTransaction(async (transaction) => {
    const codeSnapshot = await transaction.get(codeRef);
    const expiresAt: Timestamp | undefined = codeSnapshot.get("expiresAt");
    if (!codeSnapshot.exists || codeSnapshot.get("usedAt") || !expiresAt || expiresAt.toMillis() < Date.now()) {
      throw new HttpsError("not-found", "Ese código no existe, ya se usó o venció. Genera otro en VOXON 360.");
    }
    const instanceId: string = codeSnapshot.get("instanceId");
    const instanceRef = db.doc(`instances/${instanceId}`);
    const accountRef = db.doc(`accounts/${codeSnapshot.get("accountId")}`);
    const memberRef = instanceRef.collection("members").doc(uid);
    const [instance, account, member] = await Promise.all([
      transaction.get(instanceRef),
      transaction.get(accountRef),
      transaction.get(memberRef),
    ]);
    if (!instance.exists || instance.get("active") !== true) {
      throw new HttpsError("failed-precondition", "Ese negocio no está activo");
    }
    if (member.exists) {
      throw new HttpsError("already-exists", "Este equipo ya está vinculado a ese negocio");
    }
    requireDeviceRoom(account);

    const now = FieldValue.serverTimestamp();
    const number = Number(instance.get("deviceCount") ?? 0) + 1;
    transaction.set(instanceRef.collection("devices").doc(uid), {
      name: codeSnapshot.get("name"),
      platform,
      number,
      status: "active",
      enrolledAt: now,
      enrolledWith: code,
      lastSeenAt: now,
    });
    transaction.set(memberRef, { role: "locked", kind: "device", deviceNumber: number, createdAt: now });
    transaction.update(instanceRef, { deviceCount: FieldValue.increment(1) });
    transaction.update(accountRef, { "usage.devices": FieldValue.increment(1) });
    transaction.update(codeRef, { usedAt: now, usedBy: uid });

    return {
      instanceId,
      instanceName: instance.get("name"),
      mode: instance.get("mode"),
      deviceName: codeSnapshot.get("name"),
      deviceNumber: number,
    };
  });
});

/** VOXON 360 desactiva una caja: deja de ver y de vender en el negocio. */
export const revokeDevice = onCall({ invoker: "public" }, async (request) => {
  const uid = requireUid(request.auth);
  const instanceId = stringParam(request.data?.instanceId);
  const deviceUid = stringParam(request.data?.deviceUid);
  if (!deviceUid) {
    throw new HttpsError("invalid-argument", "Falta la caja");
  }
  const { instance } = await requireInstanceAdmin(instanceId, uid);

  const deviceRef = db.doc(`instances/${instanceId}/devices/${deviceUid}`);
  const memberRef = db.doc(`instances/${instanceId}/members/${deviceUid}`);
  const accountRef = db.doc(`accounts/${instance.get("accountId")}`);
  await db.runTransaction(async (transaction) => {
    const device = await transaction.get(deviceRef);
    if (!device.exists) {
      throw new HttpsError("not-found", "Esa caja no existe");
    }
    if (device.get("status") !== "active") {
      return;
    }
    transaction.update(deviceRef, { status: "revoked", revokedAt: FieldValue.serverTimestamp(), revokedBy: uid });
    transaction.delete(memberRef);
    transaction.update(accountRef, { "usage.devices": FieldValue.increment(-1) });
  });
  return { ok: true };
});

// --- Empleados ---------------------------------------------------------------

/** Crea o cambia un empleado. El PIN se guarda con hash donde ninguna app lo puede leer. */
export const saveStaff = onCall({ invoker: "public" }, async (request) => {
  const uid = requireUid(request.auth);
  const instanceId = stringParam(request.data?.instanceId);
  const staffId = stringParam(request.data?.staffId);
  const name = cleanName(request.data?.name, "el nombre del empleado", 60);
  const role = stringParam(request.data?.role);
  if (!STAFF_ROLES.includes(role)) {
    throw new HttpsError("invalid-argument", "Elige un puesto válido");
  }
  const active = request.data?.active !== false;
  const pin = request.data?.pin;
  const pinGiven = pin !== undefined && pin !== null && pin !== "";
  if ((pinGiven || !staffId) && !isValidPin(pin)) {
    throw new HttpsError("invalid-argument", "El PIN tiene de 4 a 6 números");
  }

  const { instance, isOwner } = await requireInstanceAdmin(instanceId, uid);
  if (["owner", "manager"].includes(role) && !isOwner) {
    throw new HttpsError("permission-denied", "Solo el dueño da puestos de dueño o gerente");
  }

  const staffRef = staffId
    ? db.doc(`instances/${instanceId}/staff/${staffId}`)
    : db.collection(`instances/${instanceId}/staff`).doc();
  const accountRef = db.doc(`accounts/${instance.get("accountId")}`);
  await db.runTransaction(async (transaction) => {
    const [existing, account] = await Promise.all([transaction.get(staffRef), transaction.get(accountRef)]);
    if (staffId && !existing.exists) {
      throw new HttpsError("not-found", "Ese empleado no existe");
    }
    const wasActive = existing.exists && existing.get("active") === true;
    const delta = (active ? 1 : 0) - (wasActive ? 1 : 0);
    if (delta > 0) {
      const { limits } = planOf(account);
      const used = Number(account.get("usage.users") ?? 0) + Number(account.get("usage.staff") ?? 0) + 1;
      if (!withinLimit(used, limits.users)) {
        throw new HttpsError(
          "failed-precondition",
          `Tu plan permite ${limits.users} usuarios. Sube de plan o desactiva un empleado.`,
        );
      }
    }

    const now = FieldValue.serverTimestamp();
    transaction.set(
      staffRef,
      { name, role, active, updatedAt: now, ...(existing.exists ? {} : { createdAt: now }) },
      { merge: true },
    );
    if (isValidPin(pin)) {
      transaction.set(db.doc(`instances/${instanceId}/staffSecrets/${staffRef.id}`), {
        ...hashPin(pin),
        failedAttempts: 0,
        lockedUntil: null,
        updatedAt: now,
      });
    }
    if (delta !== 0) {
      transaction.update(accountRef, { "usage.staff": FieldValue.increment(delta) });
    }
  });
  return { staffId: staffRef.id };
});

/** Caja vinculada que no tiene sesión abierta de otro negocio. */
async function requireDevice(instanceId: string, uid: string): Promise<{ member: Snapshot; device: Snapshot }> {
  if (!instanceId) {
    throw new HttpsError("invalid-argument", "Falta el negocio");
  }
  const [member, device] = await Promise.all([
    db.doc(`instances/${instanceId}/members/${uid}`).get(),
    db.doc(`instances/${instanceId}/devices/${uid}`).get(),
  ]);
  if (!member.exists || member.get("kind") !== "device" || device.get("status") !== "active") {
    throw new HttpsError("permission-denied", "Esta caja no está vinculada a este negocio");
  }
  return { member, device };
}

/** Un empleado entra en la caja con su PIN. */
export const posLogin = onCall({ invoker: "public" }, async (request) => {
  const uid = requireUid(request.auth);
  const instanceId = stringParam(request.data?.instanceId);
  const staffId = stringParam(request.data?.staffId);
  const pin = request.data?.pin;
  if (!staffId || !isValidPin(pin)) {
    throw new HttpsError("invalid-argument", "Elige tu nombre y escribe tu PIN de 4 a 6 números");
  }
  const { member, device } = await requireDevice(instanceId, uid);

  const [staff, secret] = await Promise.all([
    db.doc(`instances/${instanceId}/staff/${staffId}`).get(),
    db.doc(`instances/${instanceId}/staffSecrets/${staffId}`).get(),
  ]);
  if (!staff.exists || staff.get("active") !== true) {
    throw new HttpsError("not-found", "Ese empleado no existe o está desactivado");
  }
  const stored = secret.data() as (PinHash & { failedAttempts?: number; lockedUntil?: Timestamp | null }) | undefined;
  if (!stored) {
    throw new HttpsError("failed-precondition", "Ese empleado todavía no tiene PIN");
  }
  if ((stored.lockedUntil?.toMillis() ?? 0) > Date.now()) {
    throw new HttpsError("resource-exhausted", "Demasiados intentos. Espera unos segundos.");
  }

  if (!verifyPin(pin, stored)) {
    const failures = Number(stored.failedAttempts ?? 0) + 1;
    const locked = failures >= MAX_PIN_FAILURES;
    await secret.ref.update({
      failedAttempts: locked ? 0 : failures,
      lockedUntil: locked ? Timestamp.fromMillis(Date.now() + PIN_LOCK_MS) : null,
    });
    throw new HttpsError("permission-denied", "PIN incorrecto");
  }

  const now = FieldValue.serverTimestamp();
  await Promise.all([
    secret.ref.update({ failedAttempts: 0, lockedUntil: null }),
    member.ref.update({ role: staff.get("role"), staffId, staffName: staff.get("name"), sessionStartedAt: now }),
    device.ref.update({ lastSeenAt: now }),
  ]);
  return { staffId, name: staff.get("name"), role: staff.get("role") };
});

/** El empleado sale: la caja vuelve a quedar bloqueada. */
export const posLogout = onCall({ invoker: "public" }, async (request) => {
  const uid = requireUid(request.auth);
  const { member } = await requireDevice(stringParam(request.data?.instanceId), uid);
  await member.ref.update({ role: "locked", staffId: null, staffName: null, sessionStartedAt: null });
  return { ok: true };
});
