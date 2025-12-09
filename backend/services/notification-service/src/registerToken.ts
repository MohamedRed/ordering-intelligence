import { Firestore } from "@google-cloud/firestore";

export interface DeviceToken {
  token: string;
  userId: string;
  storeId: string;
  platform: string;
  updatedAt: string;
}

export async function registerToken(firestore: Firestore, data: DeviceToken): Promise<void> {
  await firestore.collection("deviceTokens").doc(data.token).set(data);
}
