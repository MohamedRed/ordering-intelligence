import { Firestore } from "@google-cloud/firestore";
import { GroupOrderPayment } from "./models";

export async function createPaymentRecord(firestore: Firestore, payment: GroupOrderPayment) {
  const ref = firestore
    .collection("group_orders")
    .doc(payment.groupOrderId)
    .collection("payments")
    .doc(payment.paymentId);
  await ref.set(payment, { merge: true });
}

export async function updatePaymentStatus(
  firestore: Firestore,
  groupOrderId: string,
  paymentId: string,
  status: GroupOrderPayment["status"],
  stripeCheckoutSessionId?: string,
  stripePaymentIntentId?: string
) {
  const ref = firestore
    .collection("group_orders")
    .doc(groupOrderId)
    .collection("payments")
    .doc(paymentId);
  await ref.set({ status, stripeCheckoutSessionId, stripePaymentIntentId }, { merge: true });
}

export async function updateGroupOrderPaymentRefund(
  firestore: Firestore,
  groupOrderId: string,
  paymentId: string,
  refund: {
    status?: GroupOrderPayment["status"];
    refundedAmountCents?: number;
    refundReason?: string;
    refundNote?: string;
    refundRequestedBy?: string;
    refundType?: "refund" | "void";
    stripeRefundId?: string;
    refundedAt?: string;
  }
) {
  const ref = firestore
    .collection("group_orders")
    .doc(groupOrderId)
    .collection("payments")
    .doc(paymentId);
  await ref.set(refund, { merge: true });
}

export async function listPayments(firestore: Firestore, groupOrderId: string): Promise<GroupOrderPayment[]> {
  const snap = await firestore
    .collection("group_orders")
    .doc(groupOrderId)
    .collection("payments")
    .get();
  return snap.docs.map((doc) => doc.data() as GroupOrderPayment);
}
