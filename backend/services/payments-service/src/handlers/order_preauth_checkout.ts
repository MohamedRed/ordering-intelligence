import { Request, Response } from "express";
import Stripe from "stripe";
import { Firestore } from "@google-cloud/firestore";
import { DEFAULT_CURRENCY } from "./checkout_helpers";
import { fetchOrder } from "../order_service";
import { fetchTenantStripeAccount } from "../store";
import { createOrderPaymentRecord } from "../order_payments_store";

export async function handleOrderPreauthCheckout(
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
  const { successUrl, cancelUrl, currency, amountCents } = req.body as {
    successUrl?: string;
    cancelUrl?: string;
    currency?: string;
    amountCents?: number;
  };
  if (!successUrl || !cancelUrl) {
    res.status(400).json({ error: "missing_redirect_urls" });
    return;
  }
  if (!orderServiceUrl) {
    res.status(500).json({ error: "order_service_not_configured" });
    return;
  }
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
  const authAmount = Number(amountCents || order.totalCents || 0);
  if (!Number.isFinite(authAmount) || authAmount <= 0) {
    res.status(400).json({ error: "invalid_amount" });
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
  const paymentId = `pay_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  const paymentCurrency = (currency || DEFAULT_CURRENCY).toLowerCase();
  const session = await stripe.checkout.sessions.create(
    {
      mode: "payment",
      success_url: successUrl,
      cancel_url: cancelUrl,
      line_items: [
        {
          quantity: 1,
          price_data: {
            currency: paymentCurrency,
            unit_amount: authAmount,
            product_data: {
              name: "Fuel pre-authorization"
            }
          }
        }
      ],
      payment_intent_data: {
        capture_method: "manual"
      },
      metadata: {
        order_id: orderId,
        payment_id: paymentId,
        payment_flow: "preauth"
      }
    },
    { stripeAccount }
  );
  await createOrderPaymentRecord(firestore, {
    paymentId,
    orderId,
    amountCents: authAmount,
    currency: paymentCurrency,
    status: "requires_payment",
    stripeCheckoutSessionId: session.id,
    createdAt: new Date().toISOString()
  });
  res.status(200).json({ checkoutUrl: session.url, paymentId, sessionId: session.id });
}
