import fs from "fs";
import admin from "firebase-admin";
import type { NotificationConfig } from "./types";

type FirebaseInitConfig = Pick<NotificationConfig, "FIREBASE_PROJECT_ID" | "FIREBASE_SERVICE_ACCOUNT">;

export function initializeFirebaseApp(config: FirebaseInitConfig): void {
  if (admin.apps.length > 0) {
    return;
  }

  try {
    if (!config.FIREBASE_SERVICE_ACCOUNT || config.FIREBASE_SERVICE_ACCOUNT.trim() === "") {
      admin.initializeApp({
        projectId: config.FIREBASE_PROJECT_ID
      });
      return;
    }

    const credentials = parseServiceAccount(config.FIREBASE_SERVICE_ACCOUNT);
    admin.initializeApp({
      credential: admin.credential.cert(credentials as admin.ServiceAccount),
      projectId: config.FIREBASE_PROJECT_ID
    });
  } catch (error) {
    console.error("Failed to initialise Firebase", error);
    throw error;
  }
}

export function parseServiceAccount(value: string): object {
  if (value.trim().startsWith("{")) {
    return JSON.parse(value);
  }

  const fileContents = fs.readFileSync(value, "utf-8");
  return JSON.parse(fileContents);
}
