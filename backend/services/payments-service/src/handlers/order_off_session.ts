import { Request, Response } from "express";
import Stripe from "stripe";
import { Firestore } from "@google-cloud/firestore";
import { DEFAULT_CURRENCY } from "./checkout_helpers";
import { fetchOrder } from "../order_service";
import { fetchTenantStripeAccount } from "../store";
import { createOrderPaymentRecord } from "../order_payments_store";
import { getOrCreateStripeCustomer } from "../stripe_customer";
import { STRIPE_API_VERSION } from "../stripe_client";

export async function handleOrderOffSession(
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
    sessionId,
    tenantId
  } = req.body as {
    customerId?: string;
    customerName?: string;
    amountCents?: number;
    currency?: string;
    sessionId?: string;
    tenantId?: string;
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

  const tenant = String(tenantId || order.tenantId || "").trim();
  if (!tenant) {
    res.status(400).json({ error: "missing_tenant" });
    return;
  }
  const customerId = String(customerIdRaw || order.customerId || "").trim();
  if (!customerId) {
    res.status(400).json({ error: "missing_customer" });
    return;
  }

  const stripeAccount = await fetchTenantStripeAccount(firestore, tenant);
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
    tenantId: tenant,
    customerId,
    customerName: customerName || order.customerName,
    stripeAccount
  });

  const customer = (await stripe.customers.retrieve(stripeCustomerId, {
    stripeAccount
  })) as Stripe.Customer;
  const defaultMethod =
    (customer.invoice_settings?.default_payment_method as string | null | undefined) || "";
  if (!defaultMethod) {
    res.status(409).json({ error: "default_payment_method_missing" });
    return;
  }

  let intent: Stripe.PaymentIntent;
  try {
    intent = await stripe.paymentIntents.create(
      {
        amount: total,
        currency: paymentCurrency,
        customer: stripeCustomerId,
        payment_method: defaultMethod,
        off_session: true,
        confirm: true,
        capture_method: useManualCapture ? "manual" : undefined,
        payment_method_types: ["card"],
        metadata: {
          order_id: orderId,
          payment_id: paymentId,
          tenant_id: tenant,
          customer_id: customerId,
          session_id: String(sessionId || "").trim(),
          payment_flow: fuelPaymentFlow ? String(fuelPaymentFlow) : null
        }
      },
      { stripeAccount }
    );
  } catch (err) {
    const stripeErr = err as Stripe.errors.StripeError & {
      payment_intent?: Stripe.PaymentIntent;
    };
    if (stripeErr?.payment_intent) {
      intent = stripeErr.payment_intent;
    } else {
      res.status(502).json({ error: "payment_intent_failed" });
      return;
    }
  }

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
    status: intent.status,
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
