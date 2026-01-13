import { Request, Response } from "express";
import Stripe from "stripe";
import { Firestore } from "@google-cloud/firestore";
import { fetchGroupOrder, fetchTenantStripeAccount } from "../store";
import { listPayments, updateGroupOrderPaymentRefund, updatePaymentStatus } from "../payments_store";

const REFUND_REASONS = new Set(["duplicate", "fraudulent", "requested_by_customer"]);

function parseRefundAmount(value: unknown): number | undefined {
  if (value === null || value === undefined || value === "") return undefined;
  const amount = Number(value);
  if (!Number.isFinite(amount) || amount <= 0) return undefined;
  return Math.round(amount);
}

function parseRefundReason(value: unknown): Stripe.RefundCreateParams.Reason | undefined {
  const reason = String(value || "").trim();
  if (!reason) return undefined;
  return REFUND_REASONS.has(reason) ? (reason as Stripe.RefundCreateParams.Reason) : undefined;
}

function parseTimestamp(value: string | undefined): number {
  if (!value) return 0;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

async function resolvePaymentIntentId(
  stripe: Stripe,
  stripeAccount: string,
  payment: {
    stripePaymentIntentId?: string;
    stripeCheckoutSessionId?: string;
  }
): Promise<string | undefined> {
  if (payment.stripePaymentIntentId) {
    return payment.stripePaymentIntentId;
  }
  const sessionId = payment.stripeCheckoutSessionId || "";
  if (!sessionId) {
    return undefined;
  }
  const session = await stripe.checkout.sessions.retrieve(sessionId, { stripeAccount });
  if (!session.payment_intent) {
    return undefined;
  }
  return String(session.payment_intent);
}

export async function handleGroupOrderRefund(
  req: Request,
  res: Response,
  firestore: Firestore,
  stripe: Stripe
) {
  const groupOrderId = String(req.params.groupOrderId || "").trim();
  if (!groupOrderId) {
    res.status(400).json({ error: "missing_group_order_id" });
    return;
  }

  const { amountCents, reason, note, requestedBy, paymentId, participantId } = req.body as {
    amountCents?: number;
    reason?: string;
    note?: string;
    requestedBy?: string;
    paymentId?: string;
    participantId?: string;
  };

  const paymentIdValue = String(paymentId || "").trim();
  const participantIdValue = String(participantId || "").trim();
  if (!paymentIdValue && !participantIdValue) {
    res.status(400).json({ error: "missing_payment_reference" });
    return;
  }

  const groupOrder = await fetchGroupOrder(firestore, groupOrderId);
  if (!groupOrder) {
    res.status(404).json({ error: "group_order_not_found" });
    return;
  }
  const stripeAccount = await fetchTenantStripeAccount(firestore, groupOrder.tenantId);
  if (!stripeAccount) {
    res.status(400).json({ error: "stripe_account_missing" });
    return;
  }

  const payments = await listPayments(firestore, groupOrderId);
  let candidate = payments.find((payment) => payment.paymentId === paymentIdValue);
  if (!candidate && participantIdValue) {
    const byParticipant = payments
      .filter((payment) => payment.participantId === participantIdValue)
      .sort((a, b) => parseTimestamp(b.createdAt) - parseTimestamp(a.createdAt));
    candidate = byParticipant[0];
  }
  if (!candidate) {
    res.status(404).json({ error: "payment_not_found" });
    return;
  }
  if (candidate.status !== "succeeded" && candidate.status !== "refunded") {
    res.status(409).json({ error: "payment_not_refundable" });
    return;
  }

  const amountProvided = amountCents !== undefined && amountCents !== null;
  const refundAmount = parseRefundAmount(amountCents);
  if (amountProvided && !refundAmount) {
    res.status(400).json({ error: "invalid_refund_amount" });
    return;
  }

  const refundReason = parseRefundReason(reason);
  const refundNote = String(note || "").trim();
  const refundRequestedBy = String(requestedBy || "").trim();

  const paymentIntentId = await resolvePaymentIntentId(stripe, stripeAccount, candidate);
  if (!paymentIntentId) {
    res.status(404).json({ error: "payment_intent_missing" });
    return;
  }
  if (!candidate.stripePaymentIntentId) {
    await updatePaymentStatus(
      firestore,
      groupOrderId,
      candidate.paymentId,
      candidate.status,
      candidate.stripeCheckoutSessionId,
      paymentIntentId
    );
  }

  const capturedAmount = candidate.amountCents;
  const alreadyRefunded = candidate.refundedAmountCents ?? 0;
  const remaining = Math.max(0, capturedAmount - alreadyRefunded);
  if (remaining <= 0) {
    res.status(409).json({ error: "already_refunded" });
    return;
  }
  const amountToRefund = refundAmount ?? remaining;
  if (amountToRefund <= 0 || amountToRefund > remaining) {
    res.status(400).json({ error: "invalid_refund_amount" });
    return;
  }

  const metadata: Record<string, string> = {
    group_order_id: groupOrderId,
    payment_id: candidate.paymentId,
    participant_id: candidate.participantId
  };
  if (refundNote) {
    metadata.refund_note = refundNote;
  }

  const refund = await stripe.refunds.create(
    {
      payment_intent: paymentIntentId,
      amount: amountToRefund,
      reason: refundReason,
      metadata
    },
    { stripeAccount }
  );

  const newRefundedTotal = alreadyRefunded + amountToRefund;
  const nextStatus = newRefundedTotal >= capturedAmount ? "refunded" : candidate.status;

  await updateGroupOrderPaymentRefund(firestore, groupOrderId, candidate.paymentId, {
    status: nextStatus,
    refundedAmountCents: newRefundedTotal,
    refundReason: refundReason,
    refundNote: refundNote || undefined,
    refundRequestedBy: refundRequestedBy || undefined,
    refundType: "refund",
    stripeRefundId: refund.id,
    refundedAt: new Date().toISOString()
  });

  res.status(200).json({
    groupOrderId,
    paymentId: candidate.paymentId,
    refundId: refund.id,
    amountCents: amountToRefund,
    refundedAmountCents: newRefundedTotal,
    paymentStatus: nextStatus,
    status: refund.status
  });
}
