import "dotenv/config";

import express from "express";
import cors from "cors";
import { getConfig } from "./config";
import { buildCorsOptions } from "./cors";
import { initFirestore } from "./firestore";
import { buildStripe } from "./stripe_client";
import { handleCheckout } from "./handlers/checkout";
import { handleOrderCheckout } from "./handlers/order_checkout";
import { handleOrderPreauthCheckout } from "./handlers/order_preauth_checkout";
import { handleOrderCapture } from "./handlers/order_capture";
import { handleOrderRefund } from "./handlers/order_refund";
import { handleOrderPaymentIntent } from "./handlers/order_payment_intent";
import { handleOrderOffSession } from "./handlers/order_off_session";
import { handleCustomerSetupIntent } from "./handlers/customer_setup_intent";
import {
  handleListCustomerPaymentMethods,
  handleSetDefaultCustomerPaymentMethod
} from "./handlers/customer_payment_methods";
import { handleGroupOrderPaymentIntent } from "./handlers/group_order_payment_intent";
import { handleGroupOrderOffSession } from "./handlers/group_order_off_session";
import { handleGroupOrderRefund } from "./handlers/group_order_refund";
import { handleWebhook, handleWebhookEvent } from "./handlers/webhook";
import { requireInternalAuth } from "./internal_auth";

const config = getConfig();
const firestore = initFirestore(config.FIREBASE_PROJECT_ID);
const stripe = buildStripe(config.STRIPE_SECRET_KEY);

const app = express();
app.use(cors(buildCorsOptions(config.CORS_ORIGINS)));

app.get("/healthz", (_req, res) => {
  res.status(200).json({ status: "ok", service: "payments-service", environment: config.ENVIRONMENT });
});

app.post("/group-orders/:groupOrderId/checkout", express.json(), (req, res) =>
  handleCheckout(req, res, firestore, stripe, config.NOTIFICATION_SERVICE_URL)
);

app.post("/orders/:orderId/checkout", express.json(), (req, res) =>
  handleOrderCheckout(req, res, firestore, stripe, config.ORDER_SERVICE_URL)
);

app.post("/orders/:orderId/payment-intent", express.json(), (req, res) =>
  handleOrderPaymentIntent(
    req,
    res,
    firestore,
    stripe,
    config.ORDER_SERVICE_URL,
    config.STRIPE_PUBLISHABLE_KEY
  )
);

app.post("/orders/:orderId/off-session", express.json(), (req, res) =>
  handleOrderOffSession(
    req,
    res,
    firestore,
    stripe,
    config.ORDER_SERVICE_URL,
    config.STRIPE_PUBLISHABLE_KEY
  )
);

app.post("/orders/:orderId/preauth", express.json(), (req, res) =>
  handleOrderPreauthCheckout(req, res, firestore, stripe, config.ORDER_SERVICE_URL)
);

app.post("/orders/:orderId/capture", express.json(), (req, res) =>
  handleOrderCapture(req, res, firestore, stripe, config.ORDER_SERVICE_URL)
);

app.post("/orders/:orderId/refund", express.json(), (req, res) =>
  handleOrderRefund(req, res, firestore, stripe, config.ORDER_SERVICE_URL)
);

app.post("/customers/:customerId/setup-intent", express.json(), (req, res) =>
  handleCustomerSetupIntent(req, res, firestore, stripe, config.STRIPE_PUBLISHABLE_KEY)
);

app.get("/customers/:customerId/payment-methods", (req, res) =>
  handleListCustomerPaymentMethods(req, res, firestore, stripe)
);

app.post("/customers/:customerId/payment-methods/default", express.json(), (req, res) =>
  handleSetDefaultCustomerPaymentMethod(req, res, firestore, stripe)
);

app.post("/group-orders/:groupOrderId/payment-intent", express.json(), (req, res) =>
  handleGroupOrderPaymentIntent(req, res, firestore, stripe, config.STRIPE_PUBLISHABLE_KEY)
);

app.post("/group-orders/:groupOrderId/off-session", express.json(), (req, res) =>
  handleGroupOrderOffSession(req, res, firestore, stripe, config.STRIPE_PUBLISHABLE_KEY)
);

app.post("/group-orders/:groupOrderId/refund", express.json(), (req, res) =>
  handleGroupOrderRefund(req, res, firestore, stripe)
);

const allowedWebhookEvents = config.STRIPE_WEBHOOK_ALLOWED_EVENTS
  ? config.STRIPE_WEBHOOK_ALLOWED_EVENTS.split(",").map((event) => event.trim()).filter(Boolean)
  : [];

app.post("/webhooks/stripe", express.raw({ type: "application/json", limit: "1mb" }), (req, res) =>
  handleWebhook(
    req,
    res,
    firestore,
    stripe,
    config.STRIPE_WEBHOOK_SECRET || "",
    config.ORDER_SERVICE_URL,
    config.NOTIFICATION_SERVICE_URL,
    {
      allowedEvents: allowedWebhookEvents
    }
  )
);

app.post("/internal/test/stripe-webhook", express.json({ limit: "1mb" }), async (req, res) => {
  if (!(await requireInternalAuth(req, res, config))) {
    return;
  }
  const event = req.body as any;
  if (!event || typeof event.type !== "string") {
    res.status(400).json({ error: "invalid_event" });
    return;
  }
  const result = await handleWebhookEvent(
    event,
    firestore,
    stripe,
    config.ORDER_SERVICE_URL,
    config.NOTIFICATION_SERVICE_URL,
    { allowedEvents: allowedWebhookEvents }
  );
  res.status(200).json({ received: true, ignored: result.ignored, test: true });
});

app.listen(config.PORT, () => {
  console.log(`payments-service listening on ${config.PORT}`);
});
