import { HttpsError } from "firebase-functions/v2/https";

export function requireUid(auth: { uid: string } | undefined): string {
  if (!auth?.uid) {
    throw new HttpsError("unauthenticated", "Entra con tu cuenta primero");
  }
  return auth.uid;
}

/** Texto recortado, o "" si no es texto. */
export function stringParam(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

export function cleanName(value: unknown, field: string, max = 80): string {
  const name = stringParam(value);
  if (name.length < 1 || name.length > max) {
    throw new HttpsError("invalid-argument", `Escribe ${field} (hasta ${max} caracteres)`);
  }
  return name;
}
