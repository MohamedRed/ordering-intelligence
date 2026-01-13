import { Firestore } from "@google-cloud/firestore";
import { GroupOrderSession } from "./models";

export async function fetchGroupOrder(firestore: Firestore, groupOrderId: string): Promise<GroupOrderSession | null> {
  const snap = await firestore.collection("group_orders").doc(groupOrderId).get();
  if (!snap.exists) return null;
  return snap.data() as GroupOrderSession;
}

export async function fetchTenantStripeAccount(firestore: Firestore, tenantId: string) {
  const snap = await firestore.collection("tenants").doc(tenantId).get();
  if (!snap.exists) return "";
  const data = snap.data() as Record<string, unknown>;
  return String(data?.stripe_account_id || data?.stripeAccountId || "");
}

export async function updateGroupOrderStatus(firestore: Firestore, groupOrderId: string, status: string, orderId?: string) {
  const payload: Record<string, unknown> = { status, updatedAt: new Date() };
  if (orderId) {
    payload.orderId = orderId;
  }
  await firestore.collection("group_orders").doc(groupOrderId).set(payload, { merge: true });
}
