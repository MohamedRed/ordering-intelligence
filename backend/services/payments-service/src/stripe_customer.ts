import Stripe from "stripe";
import { Firestore } from "@google-cloud/firestore";
import { fetchPaymentCustomer, savePaymentCustomer } from "./payments_customer_store";

export async function getOrCreateStripeCustomer(params: {
  firestore: Firestore;
  stripe: Stripe;
  tenantId: string;
  customerId: string;
  customerName?: string;
  stripeAccount: string;
}): Promise<{ stripeCustomerId: string }> {
  const { firestore, stripe, tenantId, customerId, customerName, stripeAccount } = params;
  const existing = await fetchPaymentCustomer(firestore, tenantId, customerId);
  if (existing?.stripeCustomerId) {
    return { stripeCustomerId: existing.stripeCustomerId };
  }

  const created = await stripe.customers.create(
    {
      name: customerName || undefined,
      metadata: {
        tenant_id: tenantId,
        customer_id: customerId
      }
    },
    { stripeAccount }
  );

  await savePaymentCustomer(firestore, {
    tenantId,
    customerId,
    stripeCustomerId: created.id,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString()
  });

  return { stripeCustomerId: created.id };
}
