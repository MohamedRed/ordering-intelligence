import admin from "firebase-admin";
import { Firestore } from "@google-cloud/firestore";

export function initFirestore(projectId?: string): Firestore {
  if (!admin.apps.length) {
    admin.initializeApp({ projectId: projectId || undefined });
  }
  return new Firestore({ projectId: projectId || undefined });
}
