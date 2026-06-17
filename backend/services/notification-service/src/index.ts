import "dotenv/config";

import express, { Request, Response } from "express";
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
import { GoogleAuth } from "google-auth-library";
import { buildNotificationCorsOptions, resolveNotificationCorsOrigins } from "./cors_policy";
import { startElevenLabsOutboundCall } from "./elevenlabs_outbound";
import { requireFirebaseAdmin, requireFirebaseUser } from "./firebase_auth";
import { initializeFirebaseApp } from "./firebase_init";
import { requireGoogleOidc, requireGoogleOidcRequest } from "./internal_auth";
import { NotificationChannels, type NotificationDeliveryChannel } from "./notification_channels";
import { enqueueReadyEscalationTask } from "./ready_escalation_tasks";
import {
  defaultMessageForStatus,
  DELIVERY_COMMS_RATE_LIMIT_DEFAULT,
  normalizeDeliveryEvent,
  normalizeDispatchEvent,
  resolveTemplateFromComms,
  safeDocId,
  toMillis
} from "./comms_helpers";
import type {
  DeliveryEvent,
  DispatchEvent,
  NotificationConfig,
  NotifyMode,
  NotifyRequest,
  OrderCustomerComms,
  OrderEvent,
  OrdersEventEnvelope,
  PubSubPushEnvelope,
  StoreDeliveryComms,
  StoreDoc,
  StoreOrderComms
} from "./types";

const config = loadConfig("notification-service") as unknown as NotificationConfig;

export const app = express();
app.use(express.json());
const notificationCorsOrigins = resolveNotificationCorsOrigins(
  process.env.CORS_ORIGINS ?? config.CORS_ORIGINS,
  config.ENVIRONMENT
);
app.use(cors(buildNotificationCorsOptions(notificationCorsOrigins)));

const port = Number(process.env.PORT || config.PORT || 8080);

initializeFirebaseApp(config);

const firestore = new Firestore({
  projectId: config.FIREBASE_PROJECT_ID || undefined
});

const firebaseAuth = getAuth();
const verifyFirebaseAdmin = requireFirebaseAdmin(firebaseAuth);
const verifyUser = requireFirebaseUser(firebaseAuth);

const messaging = admin.messaging();
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

const notificationChannels = new NotificationChannels({
  config,
  dryRun: notificationsDryRun,
  messaging,
  twilioClient,
  mailClient: sgMail
});

const googleAuth = new GoogleAuth({
  scopes: ["https://www.googleapis.com/auth/cloud-platform"]
});

const internalAuth = {
  audience: config.INTERNAL_AUTH_AUDIENCE,
  allowedEmails: config.INTERNAL_ALLOWED_EMAILS
};
const ordersEventsAuth = {
  audience: config.ORDERS_EVENTS_OIDC_AUDIENCE,
  allowedEmails: config.EVENTS_OIDC_ALLOWED_EMAILS
};
const dispatchEventsAuth = {
  audience: config.DISPATCH_EVENTS_OIDC_AUDIENCE,
  allowedEmails: config.EVENTS_OIDC_ALLOWED_EMAILS
};
const deliveriesEventsAuth = {
  audience: config.DELIVERIES_EVENTS_OIDC_AUDIENCE,
  allowedEmails: config.EVENTS_OIDC_ALLOWED_EMAILS
};
const cloudTasksAuth = {
  audience: config.CLOUD_TASKS_OIDC_AUDIENCE,
  allowedEmails: config.CLOUD_TASKS_OIDC_ALLOWED_EMAILS
};

app.get("/healthz", (_req: Request, res: Response) => {
  res.status(200).json({
    status: "ok",
    service: "notification-service",
    environment: config.ENVIRONMENT
  });
});

app.get("/metrics", requireGoogleOidc(internalAuth), (_req: Request, res: Response) => {
  res.setHeader("Content-Type", "text/plain; version=0.0.4");
  res.send(notificationChannels.metricsText());
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

app.post("/notify", requireGoogleOidc(internalAuth), async (req: Request, res: Response) => {
  const payload = req.body as NotifyRequest;
  if (!payload?.channel || !payload.payload) {
    res.status(400).json({ error: "invalid_payload" });
    return;
  }

  const results = await Promise.allSettled(
    payload.channel.map(async (channel) => {
      switch (channel) {
        case "push":
          return notificationChannels.sendPushNotification(payload, req.body.source ?? "generic");
        case "sms":
          return notificationChannels.sendSmsNotification(payload);
        case "email":
          return notificationChannels.sendEmailNotification(payload);
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

app.post("/group-orders/notify", requireGoogleOidc(internalAuth), async (req: Request, res: Response) => {
  const payload = req.body as NotifyRequest & { source?: string };
  if (!payload?.channel || !payload.payload) {
    res.status(400).json({ error: "invalid_payload" });
    return;
  }

  const results = await Promise.allSettled(
    payload.channel.map(async (channel) => {
      switch (channel) {
        case "push":
          return notificationChannels.sendPushNotification(payload, payload.source ?? "group-order");
        case "sms":
          return notificationChannels.sendSmsNotification(payload);
        case "email":
          return notificationChannels.sendEmailNotification(payload);
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
    if (!(await requireGoogleOidcRequest(req, res, ordersEventsAuth))) {
      return;
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
    const eventChannels: NotificationDeliveryChannel[] = ["push", "sms", "email"];
    const results = await Promise.allSettled([
      notificationChannels.sendPushNotification(notifyRequest, "order-event"),
      notificationChannels.sendSmsNotification(notifyRequest),
      notificationChannels.sendEmailNotification(notifyRequest)
    ]);

    const failures = results
      .map((r, idx) => ({ r, channel: eventChannels[idx] }))
      .filter((x) => x.r.status === "rejected");
    const failureDetails = failures.map((f) => {
      const reason = (f.r as PromiseRejectedResult).reason as any;
      const message = reason instanceof Error ? reason.message : String(reason);
      const code = reason && typeof reason === "object" && "code" in reason ? String(reason.code) : undefined;
      return { channel: f.channel, message, code };
    });
    failures.forEach((f) => {
      notificationChannels.recordFailure(f.channel);
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
    if (!(await requireGoogleOidcRequest(req, res, cloudTasksAuth))) {
      return;
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
    if (!(await requireGoogleOidcRequest(req, res, dispatchEventsAuth))) {
      return;
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
        await notificationChannels.sendPushNotification(notifyRequest, "dispatch_assignment_request");
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
        await notificationChannels.sendPushNotification(notifyRequest, "marketplace_offer");
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
    if (!(await requireGoogleOidcRequest(req, res, deliveriesEventsAuth))) {
      return;
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

app.post("/handoff", requireGoogleOidc(internalAuth), async (req: Request, res: Response) => {
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
    notificationChannels.sendPushNotification(notifyRequest, "handoff"),
    notificationChannels.sendSmsNotification(notifyRequest)
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

async function fetchStore(storeId: string): Promise<StoreDoc | null> {
  const snap = await firestore.collection("stores").doc(storeId).get();
  if (!snap.exists) return null;
  return snap.data() as StoreDoc;
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
      await enqueueReadyEscalationTask(googleAuth, config, { orderId: evt.id, storeId, runAtMs: Date.now() + delayMs });
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
      await notificationChannels.sendPushNotification(notifyRequest, "customer_status_update");
    }
  }

  if (notifyMode === "sms") {
    const from = String(store?.twilio_number ?? "").trim() || config.TWILIO_MESSAGING_NUMBER;
    if (!from) {
      console.warn(JSON.stringify({ level: "warn", event: "store_from_number_missing", storeId: params.storeId }));
      return;
    }
    await notificationChannels.sendCustomerSms({ to, from, body: message });
    return;
  }

  if (notifyMode === "call") {
    await startElevenLabsOutboundCall(axios, config, {
      store,
      toNumber: to,
      note: message,
      tenantId,
      storeId: params.storeId
    }, notificationsDryRun);
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
