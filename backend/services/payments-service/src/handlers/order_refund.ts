import { Request, Response } from "express";
import Stripe from "stripe";
import { Firestore } from "@google-cloud/firestore";
import { fetchOrder } from "../order_service";
import { fetchTenantStripeAccount } from "../store";
import { listOrderPayments, updateOrderPaymentRefund } from "../order_payments_store";

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

export async function handleOrderRefund(
  req: Request,
  res: Response,
  firestore: Firestore,
  stripe: Stripe,
  orderServiceUrl?: string
) {
  const orderId = String(req.params.orderId || "").trim();
  if (!orderId) {
    res.status(400).json({ error: "missing_order_id" });
    return;
  }
  if (!orderServiceUrl) {
    res.status(500).json({ error: "order_service_not_configured" });
    return;
  }

  const { amountCents, reason, note, requestedBy } = req.body as {
    amountCents?: number;
    reason?: string;
    note?: string;
    requestedBy?: string;
  };

  const order = await fetchOrder(orderServiceUrl, orderId);
  if (!order) {
    res.status(404).json({ error: "order_not_found" });
    return;
  }
  const paymentMethod = String(order.paymentMethod || "").toLowerCase();
  if (paymentMethod && paymentMethod !== "card") {
    res.status(409).json({ error: "order_not_card_payment" });
    return;
  }

  const tenantId = String(order.tenantId || "").trim();
  if (!tenantId) {
    res.status(400).json({ error: "missing_tenant" });
    return;
  }
  const stripeAccount = await fetchTenantStripeAccount(firestore, tenantId);
  if (!stripeAccount) {
    res.status(400).json({ error: "stripe_account_missing" });
    return;
  }

  const payments = await listOrderPayments(firestore, orderId);
  const candidates = payments
    .filter((payment) =>
      payment.stripePaymentIntentId &&
      (payment.status === "succeeded" || payment.status === "requires_capture" || payment.status === "refunded")
    )
    .sort((a, b) => parseTimestamp(b.createdAt) - parseTimestamp(a.createdAt));

  const candidate = candidates[0];
  if (!candidate?.stripePaymentIntentId) {
    res.status(404).json({ error: "payment_intent_missing" });
    return;
  }

  if (candidate.status === "refunded" && (candidate.refundedAmountCents || 0) >= (candidate.capturedAmountCents || candidate.amountCents)) {
    res.status(409).json({ error: "already_refunded" });
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
  const now = new Date().toISOString();

  if (candidate.status === "requires_capture") {
    await stripe.paymentIntents.cancel(candidate.stripePaymentIntentId, { stripeAccount });
    const voidAmount = candidate.amountCents || 0;
    await updateOrderPaymentRefund(firestore, orderId, candidate.paymentId, {
      status: "refunded",
      refundedAmountCents: voidAmount,
      refundReason: refundReason,
      refundNote: refundNote || undefined,
      refundRequestedBy: refundRequestedBy || undefined,
      refundType: "void",
      refundedAt: now
    });
    res.status(200).json({
      orderId,
      paymentId: candidate.paymentId,
      refundType: "void",
      amountCents: voidAmount,
      paymentStatus: "refunded"
    });
    return;
  }

  const capturedAmount = candidate.capturedAmountCents ?? candidate.amountCents;
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
    order_id: orderId,
    payment_id: candidate.paymentId
  };
  if (refundNote) {
    metadata.refund_note = refundNote;
  }

  const refund = await stripe.refunds.create(
    {
      payment_intent: candidate.stripePaymentIntentId,
      amount: amountToRefund,
      reason: refundReason,
      metadata
    },
    { stripeAccount }
  );

  const newRefundedTotal = alreadyRefunded + amountToRefund;
  const nextStatus = newRefundedTotal >= capturedAmount ? "refunded" : candidate.status;

  await updateOrderPaymentRefund(firestore, orderId, candidate.paymentId, {
    status: nextStatus,
    refundedAmountCents: newRefundedTotal,
    refundReason: refundReason,
    refundNote: refundNote || undefined,
    refundRequestedBy: refundRequestedBy || undefined,
    refundType: "refund",
    stripeRefundId: refund.id,
    refundedAt: now
  });

  res.status(200).json({
    orderId,
    paymentId: candidate.paymentId,
    refundId: refund.id,
    refundType: "refund",
    amountCents: amountToRefund,
    refundedAmountCents: newRefundedTotal,
    paymentStatus: nextStatus,
    status: refund.status
  });
}
