import { Request, Response } from "express";
import Stripe from "stripe";
import { Firestore } from "@google-cloud/firestore";
import { fetchTenantStripeAccount } from "../store";
import { getOrCreateStripeCustomer } from "../stripe_customer";
import { STRIPE_API_VERSION } from "../stripe_client";

export async function handleCustomerSetupIntent(
  req: Request,
  res: Response,
  firestore: Firestore,
  stripe: Stripe,
  publishableKey?: string
) {
  const customerId = String(req.params.customerId || "").trim();
  const tenantId = String(req.body?.tenantId || "").trim();
  const customerName = String(req.body?.customerName || "").trim();
  if (!customerId || !tenantId) {
    res.status(400).json({ error: "missing_fields" });
    return;
  }

  const stripeAccount = await fetchTenantStripeAccount(firestore, tenantId);
  if (!stripeAccount) {
    res.status(400).json({ error: "stripe_account_missing" });
    return;
  }

  const { stripeCustomerId } = await getOrCreateStripeCustomer({
    firestore,
    stripe,
    tenantId,
    customerId,
    customerName,
    stripeAccount
  });

  const intent = await stripe.setupIntents.create(
    {
      customer: stripeCustomerId,
      payment_method_types: ["card"],
      usage: "off_session",
      metadata: {
        tenant_id: tenantId,
        customer_id: customerId
      }
    },
    { stripeAccount }
  );

  const ephemeralKey = await stripe.ephemeralKeys.create(
    { customer: stripeCustomerId },
    { stripeAccount, apiVersion: STRIPE_API_VERSION }
  );

  res.status(200).json({
    setupIntentId: intent.id,
    clientSecret: intent.client_secret,
    customerId: stripeCustomerId,
    ephemeralKey: ephemeralKey.secret,
    stripeAccountId: stripeAccount,
    publishableKey: publishableKey || ""
  });
}
