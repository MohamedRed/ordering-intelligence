import { Firestore } from "@google-cloud/firestore";

export interface DeviceToken {
  token: string;
  userId: string;
  customerId?: string;
  tenantId?: string;
  storeId: string;
  platform: string;
  deviceId?: string;
  source?: string;
  updatedAt: string;
}

export async function registerToken(firestore: Firestore, data: DeviceToken): Promise<void> {
  await firestore.collection("deviceTokens").doc(data.token).set(data);
}
