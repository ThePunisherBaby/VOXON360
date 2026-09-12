import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

/** Base con nombre del proyecto voxon360-8349a (no es la "(default)"). */
export const DATABASE = "voxon360";

initializeApp();

export const db = getFirestore(DATABASE);
