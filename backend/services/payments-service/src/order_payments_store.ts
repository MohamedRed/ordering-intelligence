import { Firestore } from "@google-cloud/firestore";
import { OrderPayment } from "./models";

export async function createOrderPaymentRecord(firestore: Firestore, payment: OrderPayment) {
  const ref = firestore.collection("orders").doc(payment.orderId).collection("payments").doc(payment.paymentId);
  await ref.set(payment, { merge: true });
}

export async function updateOrderPaymentStatus(
  firestore: Firestore,
  orderId: string,
  paymentId: string,
  status: OrderPayment["status"],
  stripeCheckoutSessionId?: string,
  stripePaymentIntentId?: string,
  capturedAmountCents?: number
) {
  const ref = firestore.collection("orders").doc(orderId).collection("payments").doc(paymentId);
  await ref.set(
    { status, stripeCheckoutSessionId, stripePaymentIntentId, capturedAmountCents },
    { merge: true }
  );
}

export async function updateOrderPaymentRefund(
  firestore: Firestore,
  orderId: string,
  paymentId: string,
  refund: {
    status?: OrderPayment["status"];
    refundedAmountCents?: number;
    refundReason?: string;
    refundNote?: string;
    refundRequestedBy?: string;
    refundType?: "refund" | "void";
    stripeRefundId?: string;
    refundedAt?: string;
  }
) {
  const ref = firestore.collection("orders").doc(orderId).collection("payments").doc(paymentId);
  await ref.set(refund, { merge: true });
}

export async function listOrderPayments(
  firestore: Firestore,
  orderId: string
): Promise<OrderPayment[]> {
  const snap = await firestore.collection("orders").doc(orderId).collection("payments").get();
  return snap.docs.map((doc) => doc.data() as OrderPayment);
}
