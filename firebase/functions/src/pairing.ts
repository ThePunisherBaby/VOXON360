// Vincular una caja con QR y doble código.
//
//   VOXON POS (caja, anónima)                  VOXON 360 (celular del dueño o gerente)
//   startPairing → muestra el QR ─────────────► claimPairing(QR)        → código A (6 números)
//   confirmPairingOnDevice(código A) → código B ─► completePairing(código B) → caja vinculada
//
// El doble código prueba que quien tiene el celular está frente a la caja: con una foto del QR
// no basta. El token del QR y los códigos se guardan con hash en pairings/{id}/secrets, que
// ninguna app puede leer; cada paso admite 5 intentos y todo vence a los 10 minutos.
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { cleanName, requireUid, stringParam } from "./common";
import { enrollInTransaction, requireDeviceRoom, requireInstanceAdmin } from "./devices";
import { db } from "./firestore";
import { randomDigits, randomToken, sha256Hex } from "./security";

const PAIRING_LIFETIME_MS = 10 * 60_000;
const MAX_ATTEMPTS = 5;

type Snapshot = FirebaseFirestore.DocumentSnapshot;
type Status = "waiting" | "claimed" | "device_confirmed" | "linked" | "failed" | "cancelled";

function pairingRef(pairingId: string): FirebaseFirestore.DocumentReference {
  if (!/^[A-Za-z0-9]{10,40}$/.test(pairingId)) {
    throw new HttpsError("invalid-argument", "Ese QR no es de VOXON POS");
  }
  return db.doc(`pairings/${pairingId}`);
}

function secretsRef(ref: FirebaseFirestore.DocumentReference): FirebaseFirestore.DocumentReference {
  return ref.collection("secrets").doc("codes");
}

function statusMessage(status: string): string {
  switch (status) {
    case "linked":
      return "Esta caja ya quedó vinculada";
    case "failed":
      return "Demasiados códigos incorrectos. Empieza de nuevo en la caja.";
    case "cancelled":
      return "Se canceló la vinculación. Empieza de nuevo en la caja.";
    default:
      return "Este paso no corresponde ahora. Revisa lo que dice la caja.";
  }
}

/** La vinculación existe, no venció y está en el paso esperado. */
function requireStep(pairing: Snapshot, expected: Status): void {
  if (!pairing.exists) {
    throw new HttpsError("not-found", "Esa vinculación no existe. Pide un QR nuevo en la caja.");
  }
  const expiresAt: Timestamp | undefined = pairing.get("expiresAt");
  if (!expiresAt || expiresAt.toMillis() < Date.now()) {
    throw new HttpsError("deadline-exceeded", "La vinculación venció. Pide un QR nuevo en la caja.");
  }
  const status = pairing.get("status");
  if (status !== expected) {
    throw new HttpsError("failed-precondition", statusMessage(status));
  }
}

/** Cuenta un código incorrecto; al quinto la vinculación se cae. */
async function rejectCode(pairing: Snapshot): Promise<never> {
  const attempts = Number(pairing.get("attempts") ?? 0) + 1;
  const failed = attempts >= MAX_ATTEMPTS;
  await pairing.ref.update({ attempts, ...(failed ? { status: "failed" } : {}) });
  throw new HttpsError(
    "permission-denied",
    failed ? "Demasiados códigos incorrectos. Empieza de nuevo en la caja." : "Código incorrecto",
  );
}

function cleanCode(value: unknown): string {
  return stringParam(value).replace(/\s/g, "");
}

/** La caja nueva pide un QR. */
export const startPairing = onCall({ invoker: "public" }, async (request) => {
  const uid = requireUid(request.auth);
  const platform = stringParam(request.data?.platform).slice(0, 20) || "desconocida";

  const ref = db.collection("pairings").doc();
  const qrToken = randomToken();
  const expiresAt = Timestamp.fromMillis(Date.now() + PAIRING_LIFETIME_MS);
  const batch = db.batch();
  batch.set(ref, {
    deviceUid: uid,
    platform,
    status: "waiting",
    attempts: 0,
    claimedBy: null,
    instanceName: null,
    deviceName: null,
    createdAt: FieldValue.serverTimestamp(),
    expiresAt,
  });
  batch.set(secretsRef(ref), { qrTokenHash: sha256Hex(qrToken) });
  await batch.commit();

  return {
    pairingId: ref.id,
    qrToken,
    qr: `voxon://pair?p=${ref.id}&t=${qrToken}`,
    expiresAt: expiresAt.toDate().toISOString(),
  };
});

/** El celular escanea el QR y elige a qué negocio va la caja. Devuelve el código A. */
export const claimPairing = onCall({ invoker: "public" }, async (request) => {
  const uid = requireUid(request.auth);
  const ref = pairingRef(stringParam(request.data?.pairingId));
  const qrToken = stringParam(request.data?.qrToken);
  const instanceId = stringParam(request.data?.instanceId);
  const name = cleanName(request.data?.name || "Caja", "el nombre de la caja", 40);

  const { instance } = await requireInstanceAdmin(instanceId, uid);
  requireDeviceRoom(await db.doc(`accounts/${instance.get("accountId")}`).get());

  const mobileCode = randomDigits(6);
  const expiresAt = await db.runTransaction(async (transaction) => {
    const [pairing, secrets] = await Promise.all([transaction.get(ref), transaction.get(secretsRef(ref))]);
    requireStep(pairing, "waiting");
    if (!qrToken || sha256Hex(qrToken) !== secrets.get("qrTokenHash")) {
      throw new HttpsError("permission-denied", "Ese QR no es válido");
    }
    transaction.update(ref, {
      status: "claimed",
      instanceId,
      accountId: instance.get("accountId"),
      instanceName: instance.get("name"),
      deviceName: name,
      claimedBy: uid,
      claimedAt: FieldValue.serverTimestamp(),
      attempts: 0,
    });
    transaction.set(secretsRef(ref), { mobileCodeHash: sha256Hex(mobileCode) }, { merge: true });
    return (pairing.get("expiresAt") as Timestamp).toDate().toISOString();
  });

  return { mobileCode, instanceName: instance.get("name"), deviceName: name, expiresAt };
});

/** La caja escribe el código A del celular. Devuelve el código B. */
export const confirmPairingOnDevice = onCall({ invoker: "public" }, async (request) => {
  const uid = requireUid(request.auth);
  const ref = pairingRef(stringParam(request.data?.pairingId));
  const code = cleanCode(request.data?.code);

  const [pairing, secrets] = await Promise.all([ref.get(), secretsRef(ref).get()]);
  requireStep(pairing, "claimed");
  if (pairing.get("deviceUid") !== uid) {
    throw new HttpsError("permission-denied", "Esta vinculación es de otra caja");
  }
  if (!code || sha256Hex(code) !== secrets.get("mobileCodeHash")) {
    await rejectCode(pairing);
  }

  const posCode = randomDigits(6);
  const batch = db.batch();
  batch.update(ref, { status: "device_confirmed", attempts: 0, deviceConfirmedAt: FieldValue.serverTimestamp() });
  batch.set(secretsRef(ref), { posCodeHash: sha256Hex(posCode) }, { merge: true });
  await batch.commit();
  return { posCode };
});

/** El celular escribe el código B de la caja: la caja queda vinculada. */
export const completePairing = onCall({ invoker: "public" }, async (request) => {
  const uid = requireUid(request.auth);
  const ref = pairingRef(stringParam(request.data?.pairingId));
  const code = cleanCode(request.data?.code);

  const [pairing, secrets] = await Promise.all([ref.get(), secretsRef(ref).get()]);
  requireStep(pairing, "device_confirmed");
  if (pairing.get("claimedBy") !== uid) {
    throw new HttpsError("permission-denied", "Solo quien escaneó el QR puede terminar la vinculación");
  }
  if (!code || sha256Hex(code) !== secrets.get("posCodeHash")) {
    await rejectCode(pairing);
  }
  // Los permisos pueden haber cambiado en estos minutos.
  await requireInstanceAdmin(pairing.get("instanceId"), uid);

  const enrolled = await db.runTransaction(async (transaction) => {
    const current = await transaction.get(ref);
    requireStep(current, "device_confirmed");
    const result = await enrollInTransaction(transaction, {
      uid: current.get("deviceUid"),
      instanceId: current.get("instanceId"),
      accountId: current.get("accountId"),
      name: current.get("deviceName"),
      platform: current.get("platform"),
      source: "qr",
    });
    transaction.update(ref, {
      status: "linked",
      linkedAt: FieldValue.serverTimestamp(),
      deviceNumber: result.deviceNumber,
    });
    transaction.delete(secretsRef(ref));
    return result;
  });
  return enrolled;
});

/** La caja o quien escaneó cancelan antes de terminar. */
export const cancelPairing = onCall({ invoker: "public" }, async (request) => {
  const uid = requireUid(request.auth);
  const ref = pairingRef(stringParam(request.data?.pairingId));
  const pairing = await ref.get();
  if (!pairing.exists) {
    return { ok: true };
  }
  if (pairing.get("deviceUid") !== uid && pairing.get("claimedBy") !== uid) {
    throw new HttpsError("permission-denied", "Esta vinculación no es tuya");
  }
  if (pairing.get("status") === "linked") {
    throw new HttpsError("failed-precondition", statusMessage("linked"));
  }
  await ref.update({ status: "cancelled", cancelledAt: FieldValue.serverTimestamp() });
  return { ok: true };
});
