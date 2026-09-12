import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

/**
 * Base principal del proyecto voxon360-8349a: Firestore edición Standard, región nam5.
 * La base "voxon360" del mismo proyecto no sirve: se creó en modo compatible con MongoDB,
 * con el acceso de Firestore apagado, y ese modo no se puede cambiar.
 */
export const DATABASE = "(default)";

initializeApp();

export const db = getFirestore();
