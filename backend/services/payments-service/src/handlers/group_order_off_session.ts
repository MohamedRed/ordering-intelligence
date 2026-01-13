import { Request, Response } from "express";
import Stripe from "stripe";
import { Firestore } from "@google-cloud/firestore";
import { DEFAULT_CURRENCY, allocationForParticipant, resolvePayerId } from "./checkout_helpers";
import { fetchGroupOrder, fetchTenantStripeAccount, updateGroupOrderStatus } from "../store";
import { createPaymentRecord } from "../payments_store";
import { getOrCreateStripeCustomer } from "../stripe_customer";
import { STRIPE_API_VERSION } from "../stripe_client";

export async function handleGroupOrderOffSession(
  req: Request,
  res: Response,
  firestore: Firestore,
  stripe: Stripe,
  publishableKey?: string
) {
  const groupOrderId = String(req.params.groupOrderId || "").trim();
  if (!groupOrderId) {
    res.status(400).json({ error: "missing_group_order_id" });
    return;
  }
  const { customerId: customerIdRaw, customerName, participantId, currency, sessionId, tenantId } =
    req.body as {
      customerId?: string;
      customerName?: string;
      participantId?: string;
      currency?: string;
      sessionId?: string;
      tenantId?: string;
    };

  const groupOrder = await fetchGroupOrder(firestore, groupOrderId);
  if (!groupOrder) {
    res.status(404).json({ error: "group_order_not_found" });
    return;
  }
  if (groupOrder.status !== "locked" && groupOrder.status !== "payment_pending") {
    res.status(409).json({ error: "group_order_not_locked" });
    return;
  }
  const payerId = resolvePayerId(groupOrder, participantId);
  if (!payerId) {
    res.status(400).json({ error: "missing_participant" });
    return;
  }
  const allocation = allocationForParticipant(groupOrder.pricing?.allocations, payerId);
  if (!allocation || allocation.totalCents <= 0) {
    res.status(400).json({ error: "missing_allocation" });
    return;
  }
  const tenant = String(tenantId || groupOrder.tenantId || "").trim();
  if (!tenant) {
    res.status(400).json({ error: "missing_tenant" });
    return;
  }
  const customerId = String(customerIdRaw || "").trim();
  if (!customerId) {
    res.status(400).json({ error: "missing_customer" });
    return;
  }
  const stripeAccount = await fetchTenantStripeAccount(firestore, tenant);
  if (!stripeAccount) {
    res.status(400).json({ error: "stripe_account_missing" });
    return;
  }

  const paymentId = `pay_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  const amountCents = allocation.totalCents;
  const paymentCurrency = (currency || DEFAULT_CURRENCY).toLowerCase();

  const { stripeCustomerId } = await getOrCreateStripeCustomer({
    firestore,
    stripe,
    tenantId: tenant,
    customerId,
    customerName: customerName || "",
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
        amount: amountCents,
        currency: paymentCurrency,
        customer: stripeCustomerId,
        payment_method: defaultMethod,
        off_session: true,
        confirm: true,
        payment_method_types: ["card"],
        metadata: {
          group_order_id: groupOrderId,
          participant_id: payerId,
          payment_id: paymentId,
          tenant_id: tenant,
          customer_id: customerId,
          session_id: String(sessionId || "").trim()
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

  await createPaymentRecord(firestore, {
    paymentId,
    groupOrderId,
    participantId: payerId,
    amountCents,
    currency: paymentCurrency,
    status: "requires_payment",
    stripePaymentIntentId: intent.id,
    createdAt: new Date().toISOString()
  });

  await updateGroupOrderStatus(firestore, groupOrderId, "payment_pending");

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
    amountCents,
    currency: paymentCurrency
  });
}
