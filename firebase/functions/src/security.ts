import { pbkdf2Sync, randomBytes, randomInt, timingSafeEqual } from "node:crypto";

/** Iteraciones de PBKDF2-HMAC-SHA256 para los PIN nuevos. */
export const PIN_ITERATIONS = 60_000;

/** Sin 0, O, 1 ni I, para dictar los códigos sin equivocarse. */
export const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export interface PinHash {
  hash: string;
  salt: string;
  iterations: number;
}

export function isValidPin(pin: unknown): pin is string {
  return typeof pin === "string" && /^\d{4,6}$/.test(pin);
}

export function hashPin(pin: string, salt = randomBytes(16).toString("hex"), iterations = PIN_ITERATIONS): PinHash {
  const hash = pbkdf2Sync(pin, salt, iterations, 32, "sha256").toString("hex");
  return { hash, salt, iterations };
}

export function verifyPin(pin: string, stored: PinHash): boolean {
  if (!stored.hash || !stored.salt || !stored.iterations) {
    return false;
  }
  const candidate = pbkdf2Sync(pin, stored.salt, stored.iterations, 32, "sha256");
  const expected = Buffer.from(stored.hash, "hex");
  return expected.length === candidate.length && timingSafeEqual(candidate, expected);
}

/** Código aleatorio criptográfico con el alfabeto sin caracteres confusos. */
export function randomCode(length = 8): string {
  let code = "";
  for (let i = 0; i < length; i++) {
    code += CODE_ALPHABET.charAt(randomInt(CODE_ALPHABET.length));
  }
  return code;
}
