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

export async function listDeviceTokensForUser(
  firestore: Firestore,
  params: { userId: string; storeId?: string }
): Promise<string[]> {
  const userId = params.userId.trim();
  if (!userId) return [];
  let q = firestore.collection("deviceTokens").where("userId", "==", userId);
  if (params.storeId && params.storeId.trim()) {
    q = q.where("storeId", "==", params.storeId.trim());
  }
  const snap = await q.get();
  return snap.docs.map((d) => String(d.id)).filter((t) => t.trim().length > 0);
}

export async function listDeviceTokensForCustomer(
  firestore: Firestore,
  params: { customerId: string; storeId?: string }
): Promise<string[]> {
  const customerId = params.customerId.trim();
  if (!customerId) return [];
  let q = firestore.collection("deviceTokens").where("customerId", "==", customerId);
  if (params.storeId && params.storeId.trim()) {
    q = q.where("storeId", "==", params.storeId.trim());
  }
  const snap = await q.get();
  return snap.docs.map((d) => String(d.id)).filter((t) => t.trim().length > 0);
}
