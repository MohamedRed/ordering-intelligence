import { Request, Response } from "express";
import Stripe from "stripe";
import { Firestore } from "@google-cloud/firestore";
import { fetchGroupOrder, fetchTenantStripeAccount, updateGroupOrderStatus } from "../store";
import { createPaymentRecord } from "../payments_store";
import { allocationForParticipant, DEFAULT_CURRENCY, resolvePayerId } from "./checkout_helpers";
import { notifyPaymentLink } from "./checkout_notifications";
export async function handleCheckout(
  req: Request,
  res: Response,
  firestore: Firestore,
  stripe: Stripe,
  notificationServiceUrl?: string
) {
  const groupOrderId = String(req.params.groupOrderId || "").trim();
  if (!groupOrderId) {
    res.status(400).json({ error: "missing_group_order_id" });
    return;
  }
  const { participantId, successUrl, cancelUrl, currency } = req.body as {
    participantId?: string;
    successUrl?: string;
    cancelUrl?: string;
    currency?: string;
  };
  if (!successUrl || !cancelUrl) {
    res.status(400).json({ error: "missing_redirect_urls" });
    return;
  }
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
  const stripeAccount = await fetchTenantStripeAccount(firestore, groupOrder.tenantId);
  if (!stripeAccount) {
    res.status(400).json({ error: "stripe_account_missing" });
    return;
  }
  const paymentId = `pay_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  const amountCents = allocation.totalCents;
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
            unit_amount: amountCents,
            product_data: {
              name: "Group order"
            }
          }
        }
      ],
      metadata: {
        group_order_id: groupOrderId,
        participant_id: payerId,
        payment_id: paymentId
      }
    },
    { stripeAccount }
  );
  await createPaymentRecord(firestore, {
    paymentId,
    groupOrderId,
    participantId: payerId,
    amountCents,
    currency: paymentCurrency,
    status: "requires_payment",
    stripeCheckoutSessionId: session.id,
    createdAt: new Date().toISOString()
  });
  await updateGroupOrderStatus(firestore, groupOrderId, "payment_pending");
  const participant = groupOrder.participants?.find((entry) => entry.participantId === payerId);
  await notifyPaymentLink(notificationServiceUrl, participant, groupOrderId, paymentId, session.url || null);
  res.status(200).json({ checkoutUrl: session.url, paymentId, sessionId: session.id });
}
