import { Request, Response } from "express";
import Stripe from "stripe";
import { Firestore } from "@google-cloud/firestore";
import { listOrderPayments, updateOrderPaymentStatus } from "../order_payments_store";
import { fetchOrder } from "../order_service";
import { fetchTenantStripeAccount } from "../store";

export async function handleOrderCapture(
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
  const { amountCents } = req.body as { amountCents?: number };
  const captureAmount = Number(amountCents || 0);
  if (!Number.isFinite(captureAmount) || captureAmount <= 0) {
    res.status(400).json({ error: "invalid_amount" });
    return;
  }
  const order = await fetchOrder(orderServiceUrl, orderId);
  if (!order) {
    res.status(404).json({ error: "order_not_found" });
    return;
  }
  const stripeAccount = await fetchTenantStripeAccount(firestore, order.tenantId);
  if (!stripeAccount) {
    res.status(400).json({ error: "stripe_account_missing" });
    return;
  }
  const payments = await listOrderPayments(firestore, orderId);
  const candidate = payments.find((p) => p.stripePaymentIntentId);
  if (!candidate?.stripePaymentIntentId) {
    res.status(404).json({ error: "payment_intent_missing" });
    return;
  }
  const paymentIntentId = candidate.stripePaymentIntentId;
  await stripe.paymentIntents.capture(
    paymentIntentId,
    { amount_to_capture: captureAmount },
    { stripeAccount }
  );
  await updateOrderPaymentStatus(
    firestore,
    orderId,
    candidate.paymentId,
    "succeeded",
    candidate.stripeCheckoutSessionId,
    paymentIntentId,
    captureAmount
  );
  res.status(200).json({ ok: true });
}
