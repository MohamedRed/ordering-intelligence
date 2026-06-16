import "dotenv/config";

import express, { NextFunction, Request, Response } from "express";
import fs from "fs";
import admin from "firebase-admin";
import { Firestore } from "@google-cloud/firestore";
import sgMail from "@sendgrid/mail";
import twilio from "twilio";
import { Buffer } from "buffer";
import { listAlerts, storeAlert } from "./alerts";
import { getAuth } from "firebase-admin/auth";
import { registerToken } from "./registerToken";

import { loadConfig } from "@ordering-intelligence/config";
import cors from "cors";
import axios from "axios";
import { GoogleAuth, OAuth2Client } from "google-auth-library";
import { buildNotificationCorsOptions, resolveNotificationCorsOrigins } from "./cors_policy";

interface NotificationConfig {
  PORT: number;
  ENVIRONMENT: string;
  CORS_ORIGINS?: string;
  FIREBASE_PROJECT_ID: string;
  FIREBASE_SERVICE_ACCOUNT: string;
  TWILIO_ACCOUNT_SID?: string;
  TWILIO_AUTH_TOKEN?: string;
  TWILIO_MESSAGING_NUMBER?: string;
  SENDGRID_API_KEY?: string;
  SENDGRID_FROM_EMAIL?: string;
  ALERT_TOPIC?: string;
  OPS_PHONE?: string;
  OPS_EMAIL?: string;
  CUSTOMER_PROFILE_SERVICE_URL?: string;
  ORDERS_EVENTS_OIDC_AUDIENCE?: string;
  DISPATCH_EVENTS_OIDC_AUDIENCE?: string;
  DELIVERIES_EVENTS_OIDC_AUDIENCE?: string;

  ELEVENLABS_API_KEY?: string;
  ELEVENLABS_API_BASE_URL?: string;

  NOTIFICATIONS_DRY_RUN?: string;

  NOTIFICATION_SERVICE_URL?: string;
  CLOUD_TASKS_PROJECT_ID?: string;
  CLOUD_TASKS_LOCATION?: string;
  CLOUD_TASKS_READY_ESCALATION_QUEUE?: string;
  CLOUD_TASKS_OIDC_SERVICE_ACCOUNT_EMAIL?: string;
  CLOUD_TASKS_OIDC_AUDIENCE?: string;
}

interface NotificationPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

interface NotifyRequest {
  channel: Array<"push" | "sms" | "email">;
  target: {
    deviceTokens?: string[];
    topic?: string;
    phoneNumber?: string;
    email?: string;
  };
  payload: NotificationPayload;
}

const config = loadConfig("notification-service") as unknown as NotificationConfig;

type NotifyMode = "auto" | "sms" | "call" | "none";

type PubSubPushEnvelope = {
  message?: { data?: string; messageId?: string };
  subscription?: string;
};

type OrderStatusChange = {
  previousStatus?: string;
  newStatus?: string;
  changedAt?: string;
  changedBy?: string;
  notifyMode?: NotifyMode;
  note?: string;
  templateId?: string;
};

type OrderEvent = {
  id: string;
  storeId: string;
  status: string;
  tenantId?: string;
  customerId?: string;
  callerId?: string;
  customerName?: string;
  totalCents?: number;
  createdAt?: string;
  statusChange?: OrderStatusChange;
};

type OrderCustomerComms = {
  kind: "delay";
  notifyMode?: NotifyMode;
  note?: string;
  templateId?: string;
};

type OrdersEventEnvelope =
  | { kind: "order_customer_comms"; order: OrderEvent; comms: OrderCustomerComms; createdAt?: string }
  | { kind: string; order: OrderEvent; [k: string]: unknown };

type DispatchEvent = {
  kind: string;
  storeId: string;
  orderId?: string;
  assignmentId?: string;
  offerId?: string;
  driverId?: string;
  routeId?: string;
  createdAt?: string;
  payload?: Record<string, unknown>;
};

type DeliveryEvent = {
  kind: string;
  storeId: string;
  orderId?: string;
  deliveryId?: string;
  provider?: string;
  status?: string;
  createdAt?: string;
  payload?: Record<string, unknown>;
};

type StoreOrderCommsTemplate = { id: string; label?: string; body?: string };
type StoreOrderCommsStatus = {
  default_channel?: "sms" | "call" | "none";
  default_template_id?: string;
  templates?: StoreOrderCommsTemplate[];
};
type StoreOrderComms = {
  statuses?: Record<string, StoreOrderCommsStatus>;
  ready_escalation_enabled?: boolean;
  ready_escalation_minutes?: number;
  ready_escalation_channel?: "call" | "sms" | "none";
  rate_limit_per_hour?: number;
  arriving_soon_enabled?: boolean;
  arriving_soon_eta_threshold_minutes?: number;
};
type StoreDeliveryComms = StoreOrderComms;
type StoreDoc = {
  name?: string;
  twilio_number?: string;
  tenant_id?: string;
  store_id?: string;
  order_comms?: StoreOrderComms;
  delivery_comms?: StoreDeliveryComms;
  elevenlabs_agent_id?: string;
  elevenlabs_agent_template_id?: string;
  elevenlabs_phone_number_id?: string;
  elevenlabs_variables?: Record<string, unknown>;
};

export const app = express();
app.use(express.json());
const notificationCorsOrigins = resolveNotificationCorsOrigins(
  process.env.CORS_ORIGINS ?? config.CORS_ORIGINS,
  config.ENVIRONMENT
);
app.use(cors(buildNotificationCorsOptions(notificationCorsOrigins)));

const port = Number(process.env.PORT || config.PORT || 8080);

initializeFirebase(config.FIREBASE_SERVICE_ACCOUNT);

const firestore = new Firestore({
  projectId: config.FIREBASE_PROJECT_ID || undefined
});

// Initialise firebase-admin for token verification (already initialized above)
const firebaseAuth = getAuth();

const messaging = admin.messaging();

let pushSent = 0;
let smsSent = 0;
let emailSent = 0;
let pushFailed = 0;
let smsFailed = 0;
let emailFailed = 0;
const ALERT_TTL_DAYS = 14;
const notificationsDryRun =
  String(process.env.NOTIFICATIONS_DRY_RUN ?? config.NOTIFICATIONS_DRY_RUN ?? "").toLowerCase() === "true";

const twilioClient =
  config.TWILIO_ACCOUNT_SID && config.TWILIO_AUTH_TOKEN
    ? twilio(config.TWILIO_ACCOUNT_SID, config.TWILIO_AUTH_TOKEN)
    : undefined;

if (config.SENDGRID_API_KEY) {
  sgMail.setApiKey(config.SENDGRID_API_KEY);
}

const oidcVerifier = new OAuth2Client();
const googleAuth = new GoogleAuth({
  scopes: ["https://www.googleapis.com/auth/cloud-platform"]
});

app.get("/healthz", (_req: Request, res: Response) => {
  res.status(200).json({
    status: "ok",
    service: "notification-service",
    environment: config.ENVIRONMENT
  });
});

app.get("/metrics", (_req: Request, res: Response) => {
  res.setHeader("Content-Type", "text/plain; version=0.0.4");
  res.send(
    `notifications_push_sent_total ${pushSent}\n` +
      `notifications_sms_sent_total ${smsSent}\n` +
      `notifications_email_sent_total ${emailSent}\n` +
      `notifications_push_failed_total ${pushFailed}\n` +
      `notifications_sms_failed_total ${smsFailed}\n` +
      `notifications_email_failed_total ${emailFailed}\n` +
      `notifications_dry_run ${notificationsDryRun ? 1 : 0}\n`
  );
});

// Simple alert retrieval for admin app (read-only, auth required)
app.get("/alerts", verifyFirebaseAdmin, async (_req: Request, res: Response) => {
  try {
    const alerts = await listAlerts(firestore);
    res.status(200).json(alerts);
  } catch (err) {
    console.error("failed to list alerts", err);
    res.status(500).json({ error: "fetch_failed" });
  }
});

app.post("/notify", async (req: Request, res: Response) => {
  const payload = req.body as NotifyRequest;
  if (!payload?.channel || !payload.payload) {
    res.status(400).json({ error: "invalid_payload" });
    return;
  }

  const results = await Promise.allSettled(
    payload.channel.map(async (channel) => {
      switch (channel) {
        case "push":
          return sendPushNotification(payload, req.body.source ?? "generic");
        case "sms":
          return sendSmsNotification(payload);
        case "email":
          return sendEmailNotification(payload);
        default:
          throw new Error(`Unsupported channel ${channel}`);
      }
    })
  );

  const errors = results
    .map((result, index) => ({ result, channel: payload.channel[index] }))
    .filter((entry) => entry.result.status === "rejected");

  if (errors.length > 0) {
    console.error("Notification dispatch errors", errors);
    res.status(207).json({ status: "partial_failure", errors });
    return;
  }

  res.status(202).json({ status: "dispatched" });
});

app.post("/group-orders/notify", async (req: Request, res: Response) => {
  const payload = req.body as NotifyRequest & { source?: string };
  if (!payload?.channel || !payload.payload) {
    res.status(400).json({ error: "invalid_payload" });
    return;
  }

  const results = await Promise.allSettled(
    payload.channel.map(async (channel) => {
      switch (channel) {
        case "push":
          return sendPushNotification(payload, payload.source ?? "group-order");
        case "sms":
          return sendSmsNotification(payload);
        case "email":
          return sendEmailNotification(payload);
        default:
          throw new Error(`Unsupported channel ${channel}`);
      }
    })
  );

  const errors = results
    .map((result, index) => ({ result, channel: payload.channel[index] }))
    .filter((entry) => entry.result.status === "rejected");

  if (errors.length > 0) {
    console.error("Group-order notification errors", errors);
    res.status(207).json({ status: "partial_failure", errors });
    return;
  }

  res.status(202).json({ status: "dispatched" });
});

// Pub/Sub push endpoint for order events. Expects message.data to contain an order payload.
app.post("/events/orders", async (req: Request, res: Response) => {
  try {
    if (config.ORDERS_EVENTS_OIDC_AUDIENCE) {
      const ok = await verifyGoogleOidc(req, config.ORDERS_EVENTS_OIDC_AUDIENCE);
      if (!ok) {
        res.status(401).json({ error: "unauthorized" });
        return;
      }
    }

    const env = req.body as PubSubPushEnvelope;
    const message = env?.message;
    if (!message?.data) {
      res.status(400).json({ error: "invalid_message" });
      return;
    }
    const raw = JSON.parse(Buffer.from(message.data, "base64").toString("utf8")) as any;

    // Support both legacy payloads (raw OrderEvent) and v2 envelopes (e.g. order_customer_comms).
    const kind = String(raw?.kind ?? "").trim();
    const decoded: OrderEvent = (raw?.order && typeof raw.order === "object") ? (raw.order as OrderEvent) : (raw as OrderEvent);

    // "Notify delay" / customer comms events.
    if (kind === "order_customer_comms") {
      const env = raw as OrdersEventEnvelope;
      await handleOrderCustomerComms(decoded, (env as any).comms as OrderCustomerComms | undefined);
      res.status(204).send();
      return;
    }

    // Default behavior: record/store operational alert + status-change comms orchestration.
    const topic = `store-${decoded.storeId}-orders`;
    const notifyRequest: NotifyRequest = {
      channel: ["push"],
      target: { topic, phoneNumber: config.OPS_PHONE, email: config.OPS_EMAIL },
      payload: {
        title: `Order ${decoded.id} is ${decoded.status}`,
        body: decoded.customerName
          ? `${decoded.customerName} • total $${((decoded.totalCents ?? 0) / 100).toFixed(2)}`
          : `Status changed to ${decoded.status}`,
        data: {
          orderId: decoded.id,
          status: decoded.status,
          storeId: decoded.storeId
        }
      }
    };
    const results = await Promise.allSettled([
      sendPushNotification(notifyRequest, "order-event"),
      sendSmsNotification(notifyRequest),
      sendEmailNotification(notifyRequest)
    ]);

    const failures = results
      .map((r, idx) => ({ r, channel: ["push", "sms", "email"][idx] }))
      .filter((x) => x.r.status === "rejected");
    const failureDetails = failures.map((f) => {
      const reason = (f.r as PromiseRejectedResult).reason as any;
      const message = reason instanceof Error ? reason.message : String(reason);
      const code = reason && typeof reason === "object" && "code" in reason ? String(reason.code) : undefined;
      return { channel: f.channel, message, code };
    });
    failures.forEach((f) => {
      if (f.channel === "push") pushFailed += 1;
      if (f.channel === "sms") smsFailed += 1;
      if (f.channel === "email") emailFailed += 1;
    });

    // Persist alert (best-effort)
    await storeAlert(firestore, {
      id: decoded.id,
      title: `Order ${decoded.id} is ${decoded.status}`,
      body: notifyRequest.payload.body,
      severity: decoded.status === "cancelled" ? "warning" : "info",
      createdAt: new Date().toISOString(),
      expireAt: new Date(Date.now() + ALERT_TTL_DAYS * 24 * 60 * 60 * 1000).toISOString()
    });

    // Customer comms orchestration (only on status updates carrying statusChange metadata).
    if (decoded.statusChange?.newStatus && decoded.statusChange?.previousStatus) {
      await handleOrderStatusComms(decoded);
    }
    if (failures.length > 0) {
      console.warn(
        JSON.stringify({
          level: "warn",
          event: "order_event_partial_failure",
          orderId: decoded.id,
          failures: failures.map((f) => f.channel),
          failureDetails
        })
      );
    }
    res.status(204).send();
  } catch (err) {
    console.error("failed to process order event", err);
    res.status(500).json({ error: "processing_failed" });
  }
});

// Cloud Tasks callback (ready escalation).
app.post("/tasks/ready-escalation", async (req: Request, res: Response) => {
  try {
    if (config.CLOUD_TASKS_OIDC_AUDIENCE) {
      const ok = await verifyGoogleOidc(req, config.CLOUD_TASKS_OIDC_AUDIENCE);
      if (!ok) {
        res.status(401).json({ error: "unauthorized" });
        return;
      }
    }

    const orderId = String(req.body?.orderId ?? "").trim();
    const storeId = String(req.body?.storeId ?? "").trim();
    if (!orderId || !storeId) {
      res.status(400).json({ error: "invalid_payload" });
      return;
    }

    const orderSnap = await firestore.collection("orders").doc(orderId).get();
    if (!orderSnap.exists) {
      res.status(204).send();
      return;
    }
    const order = orderSnap.data() as any;
    if (String(order?.storeId ?? "") !== storeId) {
      res.status(204).send();
      return;
    }
    if (String(order?.status ?? "") !== "ready") {
      res.status(204).send();
      return;
    }

    const store = await fetchStore(storeId);
    const comms = store?.order_comms;
    if (!comms?.ready_escalation_enabled) {
      res.status(204).send();
      return;
    }

    // Re-use the normal comms path: outbound call by default.
    await triggerCustomerComms({
      store,
      storeId,
      status: "ready",
      notifyMode: comms.ready_escalation_channel ?? "call",
      note: "",
      templateId: "",
      tenantId: String(order?.tenantId ?? "").trim(),
      customerId: String(order?.customerId ?? "").trim(),
      callerId: String(order?.callerId ?? "").trim(),
      orderId
    });

    res.status(204).send();
  } catch (err) {
    console.error("ready escalation failed", err);
    res.status(500).json({ error: "processing_failed" });
  }
});

// Pub/Sub push endpoint for dispatch events (assignment requests, route updates).
app.post("/events/dispatch", async (req: Request, res: Response) => {
  try {
    if (config.DISPATCH_EVENTS_OIDC_AUDIENCE) {
      const ok = await verifyGoogleOidc(req, config.DISPATCH_EVENTS_OIDC_AUDIENCE);
      if (!ok) {
        res.status(401).json({ error: "unauthorized" });
        return;
      }
    }

    const env = req.body as PubSubPushEnvelope;
    const message = env?.message;
    if (!message?.data) {
      res.status(400).json({ error: "invalid_message" });
      return;
    }
    const raw = JSON.parse(Buffer.from(message.data, "base64").toString("utf8")) as DispatchEvent;
    const kind = String(raw?.kind ?? "").trim();
    const storeId = String(raw?.storeId ?? "").trim();
    const driverId = String(raw?.driverId ?? "").trim();
    const orderId = String(raw?.orderId ?? "").trim();
    const assignmentId = String(raw?.assignmentId ?? "").trim();

    if (!kind || !storeId) {
      res.status(204).send();
      return;
    }

    // v1: notify driver of assignment requests via FCM push.
    if (kind === "assignment_request" && driverId) {
      const tokens = await listDeviceTokensForUser({ userId: driverId, storeId });
      if (tokens.length > 0) {
        const notifyRequest: NotifyRequest = {
          channel: ["push"],
          target: { deviceTokens: tokens },
          payload: {
            title: "New delivery assignment",
            body: orderId ? `Order ${orderId} is ready to be picked up.` : "New assignment available.",
            data: {
              storeId,
              orderId,
              assignmentId
            }
          }
        };
        await sendPushNotification(notifyRequest, "dispatch_assignment_request");
      }
    }

    if ((kind === "marketplace_offer" || kind === "marketplace_prewarm") && driverId) {
      const tokens = await listDeviceTokensForUser({ userId: driverId });
      if (tokens.length > 0) {
        const offerId = String(raw?.payload?.offerId ?? raw?.offerId ?? "").trim();
        const notifyRequest: NotifyRequest = {
          channel: ["push"],
          target: { deviceTokens: tokens },
          payload: {
            title: kind === "marketplace_offer" ? "New delivery offer" : "Upcoming delivery opportunity",
            body: orderId
              ? `Store ${storeId} needs a courier for order ${orderId}.`
              : `Store ${storeId} may need a courier soon.`,
            data: {
              storeId,
              orderId,
              offerId
            }
          }
        };
        await sendPushNotification(notifyRequest, "marketplace_offer");
      }
    }

    const dispatchEventKey = normalizeDispatchEvent(kind);
    if (dispatchEventKey) {
      const store = await fetchStore(storeId);
      const comms = store?.delivery_comms;
      const statusCfg = comms?.statuses?.[dispatchEventKey];
      const defaultChannel = statusCfg?.default_channel ?? "none";
      if (dispatchEventKey === "arriving_soon" && !comms?.arriving_soon_enabled) {
        res.status(204).send();
        return;
      }
      if (defaultChannel !== "none") {
        const allowed = await shouldSendDeliveryComms({
          storeId,
          orderId,
          eventKey: dispatchEventKey,
          comms
        });
        if (!allowed) {
          res.status(204).send();
          return;
        }
        let tenantId = "";
        let callerId = "";
        let customerId = "";
        if (orderId) {
          const orderSnap = await firestore.collection("orders").doc(orderId).get();
          if (orderSnap.exists) {
            const order = orderSnap.data() as any;
            tenantId = String(order?.tenantId ?? "").trim();
            callerId = String(order?.callerId ?? "").trim();
            customerId = String(order?.customerId ?? "").trim();
          }
        }

        await triggerCustomerComms({
          store,
          storeId,
          status: dispatchEventKey,
          notifyMode: defaultChannel as NotifyMode,
          note: "",
          templateId: "",
          tenantId,
          customerId,
          callerId,
          orderId,
          comms
        });
      }
    }

    res.status(204).send();
  } catch (err) {
    console.error("dispatch events handler failed", err);
    res.status(500).json({ error: "processing_failed" });
  }
});

// Pub/Sub push endpoint for delivery-service events (customer delivery updates).
app.post("/events/deliveries", async (req: Request, res: Response) => {
  try {
    if (config.DELIVERIES_EVENTS_OIDC_AUDIENCE) {
      const ok = await verifyGoogleOidc(req, config.DELIVERIES_EVENTS_OIDC_AUDIENCE);
      if (!ok) {
        res.status(401).json({ error: "unauthorized" });
        return;
      }
    }

    const env = req.body as PubSubPushEnvelope;
    const message = env?.message;
    if (!message?.data) {
      res.status(400).json({ error: "invalid_message" });
      return;
    }
    const raw = JSON.parse(Buffer.from(message.data, "base64").toString("utf8")) as DeliveryEvent;
    const kind = String(raw?.kind ?? "").trim();
    const status = String(raw?.status ?? "").trim();
    const storeId = String(raw?.storeId ?? "").trim();
    const orderId = String(raw?.orderId ?? "").trim();

    if (!storeId) {
      res.status(204).send();
      return;
    }

    const eventKey = normalizeDeliveryEvent(kind, status);
    if (!eventKey) {
      res.status(204).send();
      return;
    }

    const store = await fetchStore(storeId);
    const comms = store?.delivery_comms;
    const statusCfg = comms?.statuses?.[eventKey];
    const defaultChannel = statusCfg?.default_channel ?? "none";
    if (eventKey === "arriving_soon" && !comms?.arriving_soon_enabled) {
      res.status(204).send();
      return;
    }
    if (defaultChannel === "none") {
      res.status(204).send();
      return;
    }

    const allowed = await shouldSendDeliveryComms({
      storeId,
      orderId,
      eventKey,
      comms
    });
    if (!allowed) {
      res.status(204).send();
      return;
    }

    let tenantId = "";
    let callerId = "";
    let customerId = "";
    if (orderId) {
      const orderSnap = await firestore.collection("orders").doc(orderId).get();
      if (orderSnap.exists) {
        const order = orderSnap.data() as any;
        tenantId = String(order?.tenantId ?? "").trim();
        callerId = String(order?.callerId ?? "").trim();
        customerId = String(order?.customerId ?? "").trim();
      }
    }

    await triggerCustomerComms({
      store,
      storeId,
      status: eventKey,
      notifyMode: defaultChannel as NotifyMode,
      note: "",
      templateId: "",
      tenantId,
      customerId,
      callerId,
      orderId,
      comms
    });

    res.status(204).send();
  } catch (err) {
    console.error("deliveries events handler failed", err);
    res.status(500).json({ error: "processing_failed" });
  }
});

// Device token registration (from business app). Auth required (any signed-in user).
app.post("/device-tokens", verifyUser, async (req: Request, res: Response) => {
  try {
    const token = req.body?.token as string;
    const rawStoreId = req.body?.storeId as string;
    const storeId = (rawStoreId && rawStoreId.trim().length > 0) ? rawStoreId : "marketplace";
    const platform = req.body?.platform as string ?? "unknown";
    const userId = (req as any).uid as string;
    if (!token) {
      res.status(400).json({ error: "missing_fields" });
      return;
    }
    await registerToken(firestore, {
      token,
      storeId,
      userId,
      platform,
      updatedAt: new Date().toISOString()
    });
    res.status(204).send();
  } catch (err) {
    console.error("failed to register device token", err);
    res.status(500).json({ error: "failed" });
  }
});

async function listDeviceTokensForUser(params: { userId: string; storeId?: string }): Promise<string[]> {
  const userId = params.userId.trim();
  if (!userId) return [];
  let q = firestore.collection("deviceTokens").where("userId", "==", userId);
  if (params.storeId && params.storeId.trim()) {
    q = q.where("storeId", "==", params.storeId.trim());
  }
  const snap = await q.get();
  return snap.docs.map((d) => String(d.id)).filter((t) => t.trim().length > 0);
}

async function listDeviceTokensForCustomer(params: { customerId: string; storeId?: string }): Promise<string[]> {
  const customerId = params.customerId.trim();
  if (!customerId) return [];
  let q = firestore.collection("deviceTokens").where("customerId", "==", customerId);
  if (params.storeId && params.storeId.trim()) {
    q = q.where("storeId", "==", params.storeId.trim());
  }
  const snap = await q.get();
  return snap.docs.map((d) => String(d.id)).filter((t) => t.trim().length > 0);
}

app.post("/handoff", async (req: Request, res: Response) => {
  const callSid = req.body?.callSid;
  if (!callSid) {
    res.status(400).json({ error: "missing_callSid" });
    return;
  }

  const reason = req.body?.reason ?? "unspecified";
  const body = `Call ${callSid} requires human assistance. Reason: ${reason}.`;

  const notifyRequest: NotifyRequest = {
    channel: ["push", "sms"],
    target: {
      topic: config.ALERT_TOPIC ?? "ops-alerts",
      phoneNumber: req.body?.phoneNumber
    },
    payload: {
      title: "AI call escalation",
      body,
      data: { callSid, reason }
    }
  };

  const result = await Promise.allSettled([
    sendPushNotification(notifyRequest, "handoff"),
    sendSmsNotification(notifyRequest)
  ]);

  const hasError = result.some((entry) => entry.status === "rejected");

  if (hasError) {
    res.status(500).json({ status: "failed" });
    return;
  }

  res.status(202).json({ status: "queued" });
});

if (process.env.NODE_ENV !== "test") {
  app.listen(port, () => {
    console.log(`Notification service listening on port ${port}`);
  });
}

function initializeFirebase(serviceAccount: string): void {
  if (admin.apps.length > 0) {
    return;
  }

  try {
    if (!serviceAccount || serviceAccount.trim() === "") {
      // Fall back to application default credentials (workload identity).
      admin.initializeApp({
        projectId: config.FIREBASE_PROJECT_ID
      });
    } else {
      const credentials = parseServiceAccount(serviceAccount);
      admin.initializeApp({
        credential: admin.credential.cert(credentials as admin.ServiceAccount),
        projectId: config.FIREBASE_PROJECT_ID
      });
    }
  } catch (error) {
    console.error("Failed to initialise Firebase", error);
    throw error;
  }
}

function parseServiceAccount(value: string): object {
  if (value.trim().startsWith("{")) {
    return JSON.parse(value);
  }
  const fileContents = fs.readFileSync(value, "utf-8");
  return JSON.parse(fileContents);
}

async function verifyGoogleOidc(req: Request, audience: string): Promise<boolean> {
  const authHeader = String(req.header("Authorization") ?? "");
  if (!authHeader.startsWith("Bearer ")) {
    return false;
  }
  const token = authHeader.replace("Bearer ", "").trim();
  if (!token) {
    return false;
  }
  try {
    await oidcVerifier.verifyIdToken({ idToken: token, audience });
    return true;
  } catch (err) {
    console.warn(
      JSON.stringify({
        level: "warn",
        event: "oidc_verify_failed",
        audience,
        message: (err as Error).message
      })
    );
    return false;
  }
}

async function fetchStore(storeId: string): Promise<StoreDoc | null> {
  const snap = await firestore.collection("stores").doc(storeId).get();
  if (!snap.exists) return null;
  return snap.data() as StoreDoc;
}

function resolveTemplateFromComms(
  status: string,
  comms?: StoreOrderComms | null,
  templateId?: string
): StoreOrderCommsTemplate | null {
  const statuses = comms?.statuses ?? {};
  const cfg = statuses[status] ?? statuses[String(status).toLowerCase()] ?? undefined;
  const templates = cfg?.templates ?? [];
  const explicit = String(templateId ?? "").trim();
  if (explicit) {
    const hit = templates.find((t) => String(t?.id ?? "").trim() === explicit);
    if (hit) return hit;
  }
  const def = String(cfg?.default_template_id ?? "").trim();
  if (def) {
    const hit = templates.find((t) => String(t?.id ?? "").trim() === def);
    if (hit) return hit;
  }
  return null;
}

function defaultMessageForStatus(status: string): string {
  switch (status) {
    case "confirmed":
      return "Your order has been confirmed.";
    case "ready":
      return "Your order is ready for pickup.";
    case "delivery_assigned":
      return "Your delivery is being prepared. A driver has been assigned.";
    case "picked_up":
      return "Your order has been picked up and is on the way.";
    case "out_for_delivery":
      return "Your order is out for delivery.";
    case "arriving_soon":
      return "Your driver is nearby. Arriving soon.";
    case "delivered":
      return "Delivered. Enjoy!";
    case "delivery_failed":
      return "We couldn't complete the delivery. Please contact the store.";
    case "completed":
      return "Thanks — your order is marked completed.";
    case "cancelled":
      return "Your order was cancelled. Please contact the store if you have questions.";
    case "delay":
      return "Your order is running a bit late.";
    case "pending":
    default:
      return "Your order status was updated.";
  }
}

function normalizeDeliveryEvent(kind: string, status: string): string {
  const raw = String(kind || status || "").trim().toLowerCase();
  if (!raw) return "";
  if (raw === "delivery_dispatched" || raw === "dispatched" || raw === "assigned" || raw === "delivery_assigned") {
    return "delivery_assigned";
  }
  if (raw === "picked_up" || raw === "pickup_complete" || raw === "pickup") {
    return "picked_up";
  }
  if (raw === "out_for_delivery" || raw === "en_route" || raw === "enroute" || raw === "in_transit") {
    return "out_for_delivery";
  }
  if (raw === "arriving_soon" || raw === "approaching") {
    return "arriving_soon";
  }
  if (raw === "delivered" || raw === "delivery_completed") {
    return "delivered";
  }
  if (raw === "cancelled" || raw === "canceled" || raw === "failed" || raw === "delivery_failed") {
    return "delivery_failed";
  }
  return "";
}

function normalizeDispatchEvent(kind: string): string {
  const raw = kind.trim().toLowerCase();
  if (raw === "driver_assigned") return "delivery_assigned";
  if (raw === "out_for_delivery" || raw === "en_route" || raw === "enroute") return "out_for_delivery";
  if (raw === "delivered") return "delivered";
  if (raw === "delivery_failed" || raw === "failed" || raw === "assignment_expired") return "delivery_failed";
  return "";
}

const DELIVERY_COMMS_RATE_LIMIT_DEFAULT = 3;

function safeDocId(value: string): string {
  return value.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 240);
}

function toMillis(value: any): number {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return value;
  if (typeof value === "string") {
    const ms = Date.parse(value);
    return Number.isFinite(ms) ? ms : 0;
  }
  return 0;
}

async function shouldSendDeliveryComms(params: {
  storeId: string;
  orderId?: string;
  eventKey: string;
  comms?: StoreDeliveryComms | null;
  eventVersion?: string;
}): Promise<boolean> {
  const orderId = String(params.orderId ?? "").trim();
  const eventKey = String(params.eventKey ?? "").trim();
  if (!orderId || !eventKey) return true;

  const eventVersion = String(params.eventVersion ?? "v1").trim() || "v1";
  const storeRef = firestore.collection("stores").doc(params.storeId);
  const eventDocId = safeDocId(`${orderId}_${eventKey}_${eventVersion}`);
  const eventRef = storeRef.collection("delivery_comms_events").doc(eventDocId);
  const stateRef = storeRef.collection("delivery_comms_state").doc(orderId);
  const limitRaw = Number(params.comms?.rate_limit_per_hour ?? DELIVERY_COMMS_RATE_LIMIT_DEFAULT);
  const rateLimit = Number.isFinite(limitRaw) ? limitRaw : DELIVERY_COMMS_RATE_LIMIT_DEFAULT;
  const windowMs = 60 * 60 * 1000;
  const now = Date.now();

  try {
    return await firestore.runTransaction(async (tx) => {
      const [eventSnap, stateSnap] = await Promise.all([tx.get(eventRef), tx.get(stateRef)]);
      if (eventSnap.exists) return false;

      let count = 0;
      let windowStart = now;
      if (stateSnap.exists) {
        const data = stateSnap.data() ?? {};
        const lastStart = toMillis((data as any).windowStart ?? (data as any).window_start);
        const lastCount = Number((data as any).count ?? 0);
        if (lastStart > 0 && now-lastStart < windowMs) {
          count = Number.isFinite(lastCount) ? lastCount : 0;
          windowStart = lastStart;
        }
      }

      if (rateLimit > 0 && count >= rateLimit) {
        return false;
      }

      tx.create(eventRef, {
        storeId: params.storeId,
        orderId,
        eventKey,
        eventVersion,
        createdAt: new Date(now),
      });
      tx.set(
        stateRef,
        {
          orderId,
          count: count + 1,
          windowStart: new Date(windowStart),
          updatedAt: new Date(now),
        },
        { merge: true }
      );
      return true;
    });
  } catch (err) {
    console.warn(JSON.stringify({ level: "warn", event: "delivery_comms_guardrails_failed", orderId, eventKey, message: (err as Error).message }));
    return true;
  }
}

async function handleOrderStatusComms(evt: OrderEvent): Promise<void> {
  const previousStatus = String(evt.statusChange?.previousStatus ?? "").trim();
  const newStatus = String(evt.statusChange?.newStatus ?? "").trim();
  if (!previousStatus || !newStatus) return;
  if (previousStatus === newStatus) return;

  const storeId = String(evt.storeId ?? "").trim();
  if (!storeId) return;

  const store = await fetchStore(storeId);
  const statusCfg = store?.order_comms?.statuses?.[newStatus];
  const defaultChannel = statusCfg?.default_channel ?? "none";
  const override = (evt.statusChange?.notifyMode ?? "auto") as NotifyMode;
  const effectiveMode: NotifyMode =
    override === "sms" || override === "call" || override === "none" ? override : defaultChannel;

  const note = String(evt.statusChange?.note ?? "").trim();
  const templateId = String(evt.statusChange?.templateId ?? "").trim();

  // Best-effort scheduling for ready escalation (store-configurable).
  if (newStatus === "ready") {
    const comms = store?.order_comms;
    if (comms?.ready_escalation_enabled) {
      const mins = Number(comms.ready_escalation_minutes ?? 5);
      const delayMs = Math.max(0, Math.min(60, Number.isFinite(mins) ? mins : 5)) * 60_000;
      await enqueueReadyEscalationTask({ orderId: evt.id, storeId, runAtMs: Date.now() + delayMs });
    }
  }

  await triggerCustomerComms({
    store,
    storeId,
    status: newStatus,
    notifyMode: effectiveMode,
    note,
    templateId,
    tenantId: String(evt.tenantId ?? "").trim(),
    customerId: String(evt.customerId ?? "").trim(),
    callerId: String(evt.callerId ?? "").trim(),
    orderId: String(evt.id ?? "").trim()
  });
}

async function handleOrderCustomerComms(evt: OrderEvent, comms?: OrderCustomerComms): Promise<void> {
  const storeId = String(evt.storeId ?? "").trim();
  if (!storeId) return;
  const kind = String(comms?.kind ?? "").trim();
  if (kind !== "delay") return;

  const store = await fetchStore(storeId);
  const statusCfg = store?.order_comms?.statuses?.["delay"];
  const defaultChannel = statusCfg?.default_channel ?? "none";
  const override = (comms?.notifyMode ?? "auto") as NotifyMode;
  const effectiveMode: NotifyMode =
    override === "sms" || override === "call" || override === "none" ? override : defaultChannel;

  await triggerCustomerComms({
    store,
    storeId,
    status: "delay",
    notifyMode: effectiveMode,
    note: String(comms?.note ?? "").trim(),
    templateId: String(comms?.templateId ?? "").trim(),
    tenantId: String(evt.tenantId ?? "").trim(),
    customerId: String(evt.customerId ?? "").trim(),
    callerId: String(evt.callerId ?? "").trim(),
    orderId: String(evt.id ?? "").trim()
  });
}

async function triggerCustomerComms(params: {
  store: StoreDoc | null;
  storeId: string;
  status: string;
  notifyMode: NotifyMode;
  note: string;
  templateId: string;
  tenantId: string;
  customerId?: string;
  callerId: string;
  orderId?: string;
  comms?: StoreOrderComms | null;
}): Promise<void> {
  const { store, status, notifyMode, note, templateId, tenantId, customerId, callerId, orderId, comms } = params;
  if (notifyMode === "none") return;

  const contact = await resolveCustomerContact({ tenantId, callerId });
  const to = String(contact?.phoneE164 ?? "").trim();
  if (!to) {
    console.warn(JSON.stringify({ level: "warn", event: "customer_contact_missing", tenantId, callerId }));
    return;
  }

  const template = resolveTemplateFromComms(status, comms ?? store?.order_comms ?? null, templateId);
  const message = note || String(template?.body ?? "").trim() || defaultMessageForStatus(status);
  if (!message) return;

  const pushCustomerId = String(customerId ?? "").trim();
  if (pushCustomerId) {
    const tokens = await listDeviceTokensForCustomer({ customerId: pushCustomerId, storeId: params.storeId });
    if (tokens.length > 0) {
      const notifyRequest: NotifyRequest = {
        channel: ["push"],
        target: { deviceTokens: tokens },
        payload: {
          title: store?.name ? `${store.name} update` : "Order update",
          body: message,
          data: {
            status,
            storeId: params.storeId,
            orderId: String(orderId ?? "").trim()
          }
        }
      };
      await sendPushNotification(notifyRequest, "customer_status_update");
    }
  }

  if (notifyMode === "sms") {
    const from = String(store?.twilio_number ?? "").trim() || config.TWILIO_MESSAGING_NUMBER;
    if (!from) {
      console.warn(JSON.stringify({ level: "warn", event: "store_from_number_missing", storeId: params.storeId }));
      return;
    }
    await sendCustomerSms({ to, from, body: message });
    return;
  }

  if (notifyMode === "call") {
    await startElevenLabsOutboundCall({
      store,
      toNumber: to,
      note: message,
      tenantId,
      storeId: params.storeId
    });
  }
}

async function resolveCustomerContact(params: { tenantId: string; callerId: string }): Promise<{ phoneE164?: string; customerName?: string } | null> {
  const tenantId = params.tenantId.trim();
  const callerId = params.callerId.trim();
  if (!callerId) return null;

  const base = String(config.CUSTOMER_PROFILE_SERVICE_URL ?? "").trim().replace(/\/+$/, "");
  if (!base || !tenantId) {
    return { phoneE164: callerId, customerName: "" };
  }

  const url = `${base}/v1/customers/contact?tenantId=${encodeURIComponent(tenantId)}&callerId=${encodeURIComponent(callerId)}`;
  try {
    const client = await googleAuth.getIdTokenClient(base);
    const resp = await client.request<{ data?: any }>({ url, method: "GET" });
    const data = (resp as any).data ?? {};
    return { phoneE164: String(data.phoneE164 ?? "").trim(), customerName: String(data.customerName ?? "").trim() };
  } catch (err) {
    console.warn(JSON.stringify({ level: "warn", event: "customer_profile_lookup_failed", message: (err as Error).message }));
    return { phoneE164: callerId, customerName: "" };
  }
}

async function sendCustomerSms(params: { to: string; from: string; body: string }): Promise<void> {
  if (notificationsDryRun) {
    smsSent += 1;
    console.log(JSON.stringify({ level: "info", event: "customer_sms_dry_run", to: params.to, from: params.from }));
    return;
  }
  if (!twilioClient) return;
  await twilioClient.messages.create({
    to: params.to,
    from: params.from,
    body: params.body
  });
  smsSent += 1;
  console.log(JSON.stringify({ level: "info", event: "customer_sms_sent", to: params.to, from: params.from }));
}

async function startElevenLabsOutboundCall(params: {
  store: StoreDoc | null;
  toNumber: string;
  note: string;
  tenantId: string;
  storeId: string;
}): Promise<void> {
  if (notificationsDryRun) {
    console.log(
      JSON.stringify({
        level: "info",
        event: "elevenlabs_outbound_call_dry_run",
        to: params.toNumber,
        storeId: params.storeId
      })
    );
    return;
  }
  const apiKey = String(config.ELEVENLABS_API_KEY ?? "").trim();
  if (!apiKey) {
    console.warn(JSON.stringify({ level: "warn", event: "elevenlabs_api_key_missing" }));
    return;
  }
  const base = String(config.ELEVENLABS_API_BASE_URL ?? "https://api.elevenlabs.io").replace(/\/+$/, "");
  const agentId = String(params.store?.elevenlabs_agent_id ?? "").trim() || String(params.store?.elevenlabs_agent_template_id ?? "").trim();
  const phoneNumberId = String(params.store?.elevenlabs_phone_number_id ?? "").trim();
  if (!agentId || !phoneNumberId) {
    console.warn(JSON.stringify({ level: "warn", event: "elevenlabs_store_not_configured", storeId: params.storeId }));
    return;
  }

  await axios.post(
    `${base}/v1/convai/twilio/outbound-call`,
    {
      agent_id: agentId,
      agent_phone_number_id: phoneNumberId,
      to_number: params.toNumber,
      conversation_initiation_client_data: {
        dynamic_variables: {
          tenantId: params.tenantId,
          storeId: params.storeId,
          note: params.note
        }
      }
    },
    {
      headers: {
        "xi-api-key": apiKey,
        "Content-Type": "application/json"
      },
      timeout: 15_000
    }
  );
  console.log(JSON.stringify({ level: "info", event: "elevenlabs_outbound_call_started", to: params.toNumber, storeId: params.storeId }));
}

async function enqueueReadyEscalationTask(params: { orderId: string; storeId: string; runAtMs: number }): Promise<void> {
  const projectId = String(config.CLOUD_TASKS_PROJECT_ID ?? config.FIREBASE_PROJECT_ID ?? "").trim();
  const location = String(config.CLOUD_TASKS_LOCATION ?? "").trim();
  const queue = String(config.CLOUD_TASKS_READY_ESCALATION_QUEUE ?? "").trim();
  const targetBaseUrl = String(config.NOTIFICATION_SERVICE_URL ?? "").trim().replace(/\/+$/, "");
  const oidcSa = String(config.CLOUD_TASKS_OIDC_SERVICE_ACCOUNT_EMAIL ?? "").trim();
  const oidcAudience = String(config.CLOUD_TASKS_OIDC_AUDIENCE ?? targetBaseUrl).trim();
  if (!projectId || !location || !queue || !targetBaseUrl || !oidcSa) return;

  const runAtSeconds = Math.max(0, Math.floor(params.runAtMs / 1000));
  const safeOrderId = params.orderId.replace(/[^A-Za-z0-9_-]/g, "_");
  const taskName = `projects/${projectId}/locations/${location}/queues/${queue}/tasks/ready-escalation-${safeOrderId}`;
  const url = `https://cloudtasks.googleapis.com/v2/projects/${encodeURIComponent(projectId)}/locations/${encodeURIComponent(location)}/queues/${encodeURIComponent(queue)}/tasks`;
  const bodyJson = JSON.stringify({ orderId: params.orderId, storeId: params.storeId });
  const bodyB64 = Buffer.from(bodyJson, "utf8").toString("base64");

  const client = await googleAuth.getClient();
  try {
    await (client as any).request({
      url,
      method: "POST",
      data: {
        task: {
          name: taskName,
          scheduleTime: { seconds: runAtSeconds },
          httpRequest: {
            httpMethod: "POST",
            url: `${targetBaseUrl}/tasks/ready-escalation`,
            headers: { "Content-Type": "application/json" },
            oidcToken: { serviceAccountEmail: oidcSa, audience: oidcAudience },
            body: bodyB64
          }
        }
      }
    });
  } catch (err: any) {
    // 409 ALREADY_EXISTS is fine (idempotent).
    const status = err?.response?.status;
    if (status === 409) return;
    console.warn(JSON.stringify({ level: "warn", event: "cloud_tasks_enqueue_failed", status, message: err?.message ?? String(err) }));
  }
}

async function sendPushNotification(payload: NotifyRequest, source: string): Promise<void> {
  const target = payload.target;
  if (!target.deviceTokens?.length && !target.topic) {
    throw new Error("missing push target");
  }

  const baseDataEntries = Object.entries(payload.payload.data ?? {}).map(([key, value]) => [
    key,
    String(value)
  ]);
  const baseData: Record<string, string> = Object.fromEntries([
    ["source", source],
    ...baseDataEntries
  ]);

  if (target.deviceTokens?.length) {
    if (notificationsDryRun) {
      pushSent += target.deviceTokens.length;
      console.log(
        JSON.stringify({
          level: "info",
          event: "push_multicast_dry_run",
          source,
          tokens: target.deviceTokens.length,
          title: payload.payload.title
        })
      );
    } else {
    const multicast: admin.messaging.MulticastMessage = {
      tokens: target.deviceTokens,
      data: baseData,
      notification: {
        title: payload.payload.title,
        body: payload.payload.body
      }
    };
    await messaging.sendEachForMulticast(multicast);
    pushSent += target.deviceTokens.length;
    console.log(
      JSON.stringify({
        level: "info",
        event: "push_multicast_sent",
        source,
        tokens: target.deviceTokens.length,
        title: payload.payload.title
      })
    );
    }
  }

  if (target.topic) {
    if (notificationsDryRun) {
      pushSent += 1;
      console.log(
        JSON.stringify({
          level: "info",
          event: "push_topic_dry_run",
          source,
          topic: target.topic,
          title: payload.payload.title
        })
      );
      return;
    }
    const message: admin.messaging.Message = {
      topic: target.topic,
      data: baseData,
      notification: {
        title: payload.payload.title,
        body: payload.payload.body
      }
    };
    await messaging.send(message);
    pushSent += 1;
    console.log(
      JSON.stringify({
        level: "info",
        event: "push_topic_sent",
        source,
        topic: target.topic,
        title: payload.payload.title
      })
    );
  }
}

async function sendSmsNotification(payload: NotifyRequest): Promise<void> {
  if (notificationsDryRun) {
    smsSent += 1;
    console.log(
      JSON.stringify({
        level: "info",
        event: "sms_dry_run",
        to: payload.target.phoneNumber ?? config.OPS_PHONE,
        title: payload.payload.title
      })
    );
    return;
  }
  if (!twilioClient) {
    return;
  }
  const phoneNumber = payload.target.phoneNumber ?? config.OPS_PHONE;
  if (!phoneNumber) {
    throw new Error("missing phoneNumber for sms channel");
  }
  if (!config.TWILIO_MESSAGING_NUMBER) {
    throw new Error("missing TWILIO_MESSAGING_NUMBER");
  }

  await twilioClient.messages.create({
    to: phoneNumber,
    from: config.TWILIO_MESSAGING_NUMBER,
    body: payload.payload.body
  });
  smsSent += 1;
  console.log(
    JSON.stringify({
      level: "info",
      event: "sms_sent",
      to: phoneNumber,
      title: payload.payload.title
    })
  );
}

async function sendEmailNotification(payload: NotifyRequest): Promise<void> {
  if (notificationsDryRun) {
    emailSent += 1;
    console.log(
      JSON.stringify({
        level: "info",
        event: "email_dry_run",
        to: payload.target.email ?? config.OPS_EMAIL,
        title: payload.payload.title
      })
    );
    return;
  }
  if (!config.SENDGRID_API_KEY) {
    return;
  }
  const email = payload.target.email ?? config.OPS_EMAIL;
  if (!email) {
    throw new Error("missing email target");
  }

  await sgMail.send({
    to: email,
    from: config.SENDGRID_FROM_EMAIL ?? "alerts@ordering-intelligence.test",
    subject: payload.payload.title,
    text: payload.payload.body
  });
  emailSent += 1;
  console.log(
    JSON.stringify({
      level: "info",
      event: "email_sent",
      to: email,
      title: payload.payload.title
    })
  );
}

async function verifyFirebaseAdmin(req: Request, res: Response, next: NextFunction) {
  try {
    const authHeader = req.header("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return res.status(401).json({ error: "missing_auth" });
    }
    const token = authHeader.replace("Bearer ", "");
    const decoded = await firebaseAuth.verifyIdToken(token);
    if (decoded.role && decoded.role !== "admin") {
      return res.status(403).json({ error: "forbidden" });
    }
    return next();
  } catch (err) {
    console.error("auth failed", err);
    return res.status(401).json({ error: "unauthorized" });
  }
}

async function verifyUser(req: Request, res: Response, next: NextFunction) {
  try {
    const authHeader = req.header("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return res.status(401).json({ error: "missing_auth" });
    }
    const token = authHeader.replace("Bearer ", "");
    const decoded = await firebaseAuth.verifyIdToken(token);
    (req as any).uid = decoded.uid;
    return next();
  } catch (err) {
    console.error("auth failed", err);
    return res.status(401).json({ error: "unauthorized" });
  }
}
