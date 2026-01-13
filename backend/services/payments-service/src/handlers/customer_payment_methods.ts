import { Request, Response } from "express";
import Stripe from "stripe";
import { Firestore } from "@google-cloud/firestore";
import { fetchTenantStripeAccount } from "../store";
import { getOrCreateStripeCustomer } from "../stripe_customer";

export async function handleListCustomerPaymentMethods(
  req: Request,
  res: Response,
  firestore: Firestore,
  stripe: Stripe
) {
  const customerId = String(req.params.customerId || "").trim();
  const tenantId = String(req.query.tenantId || "").trim();
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
    customerName: "",
    stripeAccount
  });

  const methods = await stripe.paymentMethods.list(
    { customer: stripeCustomerId, type: "card" },
    { stripeAccount }
  );

  const customer = (await stripe.customers.retrieve(stripeCustomerId, {
    stripeAccount
  })) as Stripe.Customer;
  const defaultId = customer.invoice_settings?.default_payment_method as
    | string
    | null
    | undefined;

  res.status(200).json({
    methods: methods.data.map((method) => ({
      id: method.id,
      brand: method.card?.brand || "",
      last4: method.card?.last4 || "",
      expMonth: method.card?.exp_month || 0,
      expYear: method.card?.exp_year || 0,
      isDefault: defaultId === method.id
    }))
  });
}

export async function handleSetDefaultCustomerPaymentMethod(
  req: Request,
  res: Response,
  firestore: Firestore,
  stripe: Stripe
) {
  const customerId = String(req.params.customerId || "").trim();
  const tenantId = String(req.body?.tenantId || "").trim();
  const paymentMethodId = String(req.body?.paymentMethodId || "").trim();
  if (!customerId || !tenantId || !paymentMethodId) {
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
    customerName: "",
    stripeAccount
  });

  await stripe.customers.update(
    stripeCustomerId,
    {
      invoice_settings: {
        default_payment_method: paymentMethodId
      }
    },
    { stripeAccount }
  );

  res.status(200).json({ status: "ok" });
}
