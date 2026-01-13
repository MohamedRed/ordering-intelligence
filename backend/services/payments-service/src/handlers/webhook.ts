import { Request, Response } from "express";
import Stripe from "stripe";
import { Firestore } from "@google-cloud/firestore";
import { listPayments, updatePaymentStatus } from "../payments_store";
import { updateOrderPaymentStatus } from "../order_payments_store";
import { fetchGroupOrder, fetchTenantStripeAccount, updateGroupOrderStatus } from "../store";
import { submitGroupOrder, updateOrderStatus } from "../order_service";
import { sendGroupOrderNotification } from "../notification_service";

export async function handleWebhook(
  req: Request,
  res: Response,
  firestore: Firestore,
  stripe: Stripe,
  webhookSecret: string,
  orderServiceUrl?: string,
  notificationServiceUrl?: string
) {
  const sig = req.headers["stripe-signature"] as string | undefined;
  if (!sig || !webhookSecret) {
    res.status(400).send("missing_signature");
    return;
  }
  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(req.body, sig, webhookSecret);
  } catch (err) {
    res.status(400).send("invalid_signature");
    return;
  }

  if (event.type === "checkout.session.completed") {
    const session = event.data.object as Stripe.Checkout.Session;
    const meta = session.metadata || {};
    const groupOrderId = String(meta.group_order_id || "");
    const orderId = String(meta.order_id || "");
    const paymentId = String(meta.payment_id || "");
    const paymentFlow = String(meta.payment_flow || "");
    const paymentIntentId = session.payment_intent ? String(session.payment_intent) : undefined;
    if (orderId && paymentId) {
      const status = paymentFlow === "preauth" ? "requires_capture" : "succeeded";
      await updateOrderPaymentStatus(
        firestore,
        orderId,
        paymentId,
        status,
        session.id,
        paymentIntentId
      );
      if (orderServiceUrl) {
        try {
          await updateOrderStatus(orderServiceUrl, orderId, "confirmed");
        } catch (err) {
          console.error("order status update failed", err);
        }
      }
    }
    if (groupOrderId && paymentId) {
      const groupOrder = await fetchGroupOrder(firestore, groupOrderId);
      const previousStatus = groupOrder?.status || "";
      const sessionIntentId = session.payment_intent ? String(session.payment_intent) : undefined;
      await updatePaymentStatus(
        firestore,
        groupOrderId,
        paymentId,
        "succeeded",
        session.id,
        sessionIntentId
      );
      const payments = await listPayments(firestore, groupOrderId);
      const allPaid = payments.length > 0 && payments.every((p) => p.status === "succeeded");
      if (allPaid) {
        if (previousStatus !== "paid" && previousStatus !== "submitted") {
          try {
            await sendGroupOrderNotification(notificationServiceUrl, groupOrder?.host, {
              title: "Group order paid",
              body: `All participants have paid for group order ${groupOrderId}.`,
              data: { groupOrderId }
            });
          } catch (err) {
            console.error("group order paid notification failed", err);
          }
        }
        await updateGroupOrderStatus(firestore, groupOrderId, "paid");
        if (orderServiceUrl && previousStatus !== "submitted") {
          await submitGroupOrder(orderServiceUrl, groupOrderId);
          await updateGroupOrderStatus(firestore, groupOrderId, "submitted");
          try {
            await sendGroupOrderNotification(notificationServiceUrl, groupOrder?.host, {
              title: "Group order submitted",
              body: `Group order ${groupOrderId} has been submitted to the store.`,
              data: { groupOrderId }
            });
          } catch (err) {
            console.error("group order submitted notification failed", err);
          }
        }
      } else {
        if (previousStatus != "payment_pending") {
          await updateGroupOrderStatus(firestore, groupOrderId, "payment_pending");
        }
      }
    }
  }

  if (event.type === "payment_intent.succeeded") {
    const intent = event.data.object as Stripe.PaymentIntent;
    const meta = intent.metadata || {};
    const orderId = String(meta.order_id || "");
    const groupOrderId = String(meta.group_order_id || "");
    const paymentId = String(meta.payment_id || "");
    const paymentFlow = String(meta.payment_flow || "");
    if (orderId && paymentId) {
      const status = paymentFlow === "preauth" ? "requires_capture" : "succeeded";
      await updateOrderPaymentStatus(
        firestore,
        orderId,
        paymentId,
        status,
        undefined,
        intent.id
      );
      if (orderServiceUrl) {
        try {
          await updateOrderStatus(orderServiceUrl, orderId, "confirmed");
        } catch (err) {
          console.error("order status update failed", err);
        }
      }
    }
    if (groupOrderId && paymentId) {
      await handleGroupOrderPaymentSuccess(
        firestore,
        orderServiceUrl,
        notificationServiceUrl,
        groupOrderId,
        paymentId,
        intent.id
      );
    }
    await setDefaultPaymentMethodFromIntent(firestore, stripe, intent, event.account);
  }

  if (event.type === "payment_intent.payment_failed") {
    const intent = event.data.object as Stripe.PaymentIntent;
    const meta = intent.metadata || {};
    const orderId = String(meta.order_id || "");
    const groupOrderId = String(meta.group_order_id || "");
    const paymentId = String(meta.payment_id || "");
    if (orderId && paymentId) {
      await updateOrderPaymentStatus(
        firestore,
        orderId,
        paymentId,
        "failed",
        undefined,
        intent.id
      );
    }
    if (groupOrderId && paymentId) {
      await updatePaymentStatus(firestore, groupOrderId, paymentId, "failed", undefined, intent.id);
    }
  }

  if (event.type === "setup_intent.succeeded") {
    const setupIntent = event.data.object as Stripe.SetupIntent;
    await setDefaultPaymentMethodFromSetupIntent(
      firestore,
      stripe,
      setupIntent,
      event.account
    );
  }

  if (event.type === "checkout.session.expired") {
    const session = event.data.object as Stripe.Checkout.Session;
    const meta = session.metadata || {};
    const groupOrderId = String(meta.group_order_id || "");
    const orderId = String(meta.order_id || "");
    const paymentId = String(meta.payment_id || "");
    if (orderId && paymentId) {
      await updateOrderPaymentStatus(firestore, orderId, paymentId, "expired", session.id);
    }
    if (groupOrderId && paymentId) {
      const sessionIntentId = session.payment_intent ? String(session.payment_intent) : undefined;
      await updatePaymentStatus(
        firestore,
        groupOrderId,
        paymentId,
        "expired",
        session.id,
        sessionIntentId
      );
    }
  }

  res.status(200).json({ received: true });
}

async function handleGroupOrderPaymentSuccess(
  firestore: Firestore,
  orderServiceUrl: string | undefined,
  notificationServiceUrl: string | undefined,
  groupOrderId: string,
  paymentId: string,
  paymentIntentId?: string
) {
  const groupOrder = await fetchGroupOrder(firestore, groupOrderId);
  const previousStatus = groupOrder?.status || "";
  await updatePaymentStatus(
    firestore,
    groupOrderId,
    paymentId,
    "succeeded",
    undefined,
    paymentIntentId
  );
  const payments = await listPayments(firestore, groupOrderId);
  const allPaid = payments.length > 0 && payments.every((p) => p.status === "succeeded");
  if (allPaid) {
    if (previousStatus !== "paid" && previousStatus !== "submitted") {
      try {
        await sendGroupOrderNotification(notificationServiceUrl, groupOrder?.host, {
          title: "Group order paid",
          body: `All participants have paid for group order ${groupOrderId}.`,
          data: { groupOrderId }
        });
      } catch (err) {
        console.error("group order paid notification failed", err);
      }
    }
    await updateGroupOrderStatus(firestore, groupOrderId, "paid");
    if (orderServiceUrl && previousStatus !== "submitted") {
      await submitGroupOrder(orderServiceUrl, groupOrderId);
      await updateGroupOrderStatus(firestore, groupOrderId, "submitted");
      try {
        await sendGroupOrderNotification(notificationServiceUrl, groupOrder?.host, {
          title: "Group order submitted",
          body: `Group order ${groupOrderId} has been submitted to the store.`,
          data: { groupOrderId }
        });
      } catch (err) {
        console.error("group order submitted notification failed", err);
      }
    }
  } else if (previousStatus != "payment_pending") {
    await updateGroupOrderStatus(firestore, groupOrderId, "payment_pending");
  }
}

async function resolveStripeAccount(
  firestore: Firestore,
  tenantId: string,
  eventAccount?: string | null
): Promise<string | undefined> {
  if (eventAccount) return eventAccount;
  if (!tenantId) return undefined;
  return fetchTenantStripeAccount(firestore, tenantId);
}

async function setDefaultPaymentMethodFromIntent(
  firestore: Firestore,
  stripe: Stripe,
  intent: Stripe.PaymentIntent,
  eventAccount?: string | null
) {
  const customerId = typeof intent.customer === "string" ? intent.customer : "";
  const paymentMethodId = typeof intent.payment_method === "string" ? intent.payment_method : "";
  if (!customerId || !paymentMethodId) return;
  const tenantId = String(intent.metadata?.tenant_id || "").trim();
  const stripeAccount = await resolveStripeAccount(firestore, tenantId, eventAccount);
  if (!stripeAccount) return;
  try {
    await stripe.customers.update(
      customerId,
      { invoice_settings: { default_payment_method: paymentMethodId } },
      { stripeAccount }
    );
  } catch (err) {
    console.error("default payment method update failed", err);
  }
}

async function setDefaultPaymentMethodFromSetupIntent(
  firestore: Firestore,
  stripe: Stripe,
  intent: Stripe.SetupIntent,
  eventAccount?: string | null
) {
  const customerId = typeof intent.customer === "string" ? intent.customer : "";
  const paymentMethodId = typeof intent.payment_method === "string" ? intent.payment_method : "";
  if (!customerId || !paymentMethodId) return;
  const tenantId = String(intent.metadata?.tenant_id || "").trim();
  const stripeAccount = await resolveStripeAccount(firestore, tenantId, eventAccount);
  if (!stripeAccount) return;
  try {
    await stripe.customers.update(
      customerId,
      { invoice_settings: { default_payment_method: paymentMethodId } },
      { stripeAccount }
    );
  } catch (err) {
    console.error("setup intent default update failed", err);
  }
}
