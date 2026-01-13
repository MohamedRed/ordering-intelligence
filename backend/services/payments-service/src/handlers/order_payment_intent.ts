import { Request, Response } from "express";
import Stripe from "stripe";
import { Firestore } from "@google-cloud/firestore";
import { DEFAULT_CURRENCY } from "./checkout_helpers";
import { fetchOrder } from "../order_service";
import { fetchTenantStripeAccount } from "../store";
import { createOrderPaymentRecord } from "../order_payments_store";
import { getOrCreateStripeCustomer } from "../stripe_customer";
import { STRIPE_API_VERSION } from "../stripe_client";

export async function handleOrderPaymentIntent(
  req: Request,
  res: Response,
  firestore: Firestore,
  stripe: Stripe,
  orderServiceUrl?: string,
  publishableKey?: string
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

  const {
    customerId: customerIdRaw,
    customerName,
    amountCents,
    currency,
    savePaymentMethod,
    sessionId
  } = req.body as {
    customerId?: string;
    customerName?: string;
    amountCents?: number;
    currency?: string;
    savePaymentMethod?: boolean;
    sessionId?: string;
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
  const fuelPaymentFlow = String(order.fuelPaymentFlow || "").toLowerCase();
  const useManualCapture = fuelPaymentFlow === "preauth";

  const tenantId = String(order.tenantId || "").trim();
  if (!tenantId) {
    res.status(400).json({ error: "missing_tenant" });
    return;
  }

  const customerId = String(customerIdRaw || order.customerId || "").trim();
  if (!customerId) {
    res.status(400).json({ error: "missing_customer" });
    return;
  }

  const stripeAccount = await fetchTenantStripeAccount(firestore, tenantId);
  if (!stripeAccount) {
    res.status(400).json({ error: "stripe_account_missing" });
    return;
  }

  const total = Number(amountCents ?? order.totalCents ?? 0);
  if (!Number.isFinite(total) || total <= 0) {
    res.status(400).json({ error: "invalid_amount" });
    return;
  }

  const paymentCurrency = (currency || DEFAULT_CURRENCY).toLowerCase();
  const paymentId = `pay_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;

  const { stripeCustomerId } = await getOrCreateStripeCustomer({
    firestore,
    stripe,
    tenantId,
    customerId,
    customerName: customerName || order.customerName,
    stripeAccount
  });

  const intent = await stripe.paymentIntents.create(
    {
      amount: total,
      currency: paymentCurrency,
      customer: stripeCustomerId,
      setup_future_usage: savePaymentMethod === false ? undefined : "off_session",
      capture_method: useManualCapture ? "manual" : undefined,
      automatic_payment_methods: { enabled: true },
      metadata: {
        order_id: orderId,
        payment_id: paymentId,
        tenant_id: tenantId,
        customer_id: customerId,
        session_id: String(sessionId || "").trim(),
        payment_flow: fuelPaymentFlow ? String(fuelPaymentFlow) : null
      }
    },
    { stripeAccount }
  );

  await createOrderPaymentRecord(firestore, {
    paymentId,
    orderId,
    amountCents: total,
    currency: paymentCurrency,
    status: "requires_payment",
    stripePaymentIntentId: intent.id,
    createdAt: new Date().toISOString()
  });

  const ephemeralKey = await stripe.ephemeralKeys.create(
    { customer: stripeCustomerId },
    { stripeAccount, apiVersion: STRIPE_API_VERSION }
  );

  res.status(200).json({
    paymentId,
    paymentIntentId: intent.id,
    clientSecret: intent.client_secret,
    customerId: stripeCustomerId,
    ephemeralKey: ephemeralKey.secret,
    stripeAccountId: stripeAccount,
    publishableKey: publishableKey || "",
    amountCents: total,
    currency: paymentCurrency
  });
}
