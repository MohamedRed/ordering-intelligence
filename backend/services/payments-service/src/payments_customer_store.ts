import { Firestore } from "@google-cloud/firestore";

export type PaymentCustomer = {
  tenantId: string;
  customerId: string;
  stripeCustomerId: string;
  createdAt: string;
  updatedAt: string;
};

function customerDocId(tenantId: string, customerId: string): string {
  const raw = `${tenantId}:${customerId}`.trim();
  return raw.replace(/[^a-zA-Z0-9_-]/g, "_");
}

export async function fetchPaymentCustomer(
  firestore: Firestore,
  tenantId: string,
  customerId: string
): Promise<PaymentCustomer | null> {
  const docId = customerDocId(tenantId, customerId);
  const snap = await firestore.collection("payment_customers").doc(docId).get();
  if (!snap.exists) return null;
  return snap.data() as PaymentCustomer;
}

export async function savePaymentCustomer(
  firestore: Firestore,
  customer: PaymentCustomer
): Promise<void> {
  const docId = customerDocId(customer.tenantId, customer.customerId);
  await firestore.collection("payment_customers").doc(docId).set(customer, { merge: true });
}
