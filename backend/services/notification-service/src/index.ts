import "dotenv/config";

import express, { Request, Response } from "express";
import fs from "fs";
import admin from "firebase-admin";
import { Firestore } from "@google-cloud/firestore";
import sgMail from "@sendgrid/mail";
import twilio from "twilio";
import { Buffer } from "buffer";
import { listAlerts, storeAlert } from "./alerts";
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { registerToken } from "./registerToken";

import { loadConfig } from "@ordering-intelligence/config";

interface NotificationConfig {
  PORT: number;
  ENVIRONMENT: string;
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

export const app = express();
app.use(express.json());

const port = Number(config.PORT ?? 8084);

initializeFirebase(config.FIREBASE_SERVICE_ACCOUNT);

const firestore = new Firestore({
  projectId: config.FIREBASE_PROJECT_ID || undefined
});

// Initialise firebase-admin for token verification
initializeApp();
const firebaseAuth = getAuth();

const messaging = admin.messaging();

let pushSent = 0;
let smsSent = 0;
let emailSent = 0;
let pushFailed = 0;
let smsFailed = 0;
let emailFailed = 0;
const ALERT_TTL_DAYS = 14;

const twilioClient =
  config.TWILIO_ACCOUNT_SID && config.TWILIO_AUTH_TOKEN && config.TWILIO_MESSAGING_NUMBER
    ? twilio(config.TWILIO_ACCOUNT_SID, config.TWILIO_AUTH_TOKEN)
    : undefined;

if (config.SENDGRID_API_KEY) {
  sgMail.setApiKey(config.SENDGRID_API_KEY);
}

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
      `notifications_email_failed_total ${emailFailed}\n`
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

// Pub/Sub push endpoint for order events. Expects message.data to contain an order payload.
app.post("/events/orders", async (req: Request, res: Response) => {
  try {
    const message = req.body?.message;
    if (!message?.data) {
      res.status(400).json({ error: "invalid_message" });
      return;
    }
    const decoded = JSON.parse(Buffer.from(message.data, "base64").toString("utf8")) as {
      id: string;
      storeId: string;
      status: string;
      customerName?: string;
      totalCents?: number;
      createdAt?: string;
    };
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
    if (failures.length > 0) {
      console.warn(
        JSON.stringify({
          level: "warn",
          event: "order_event_partial_failure",
          orderId: decoded.id,
          failures: failures.map((f) => f.channel)
        })
      );
    }
    res.status(204).send();
  } catch (err) {
    console.error("failed to process order event", err);
    res.status(500).json({ error: "processing_failed" });
  }
});

// Device token registration (from business app). Auth required (any signed-in user).
app.post("/device-tokens", verifyUser, async (req: Request, res: Response) => {
  try {
    const token = req.body?.token as string;
    const storeId = req.body?.storeId as string;
    const platform = req.body?.platform as string ?? "unknown";
    const userId = (req as any).uid as string;
    if (!token || !storeId) {
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
    const credentials = parseServiceAccount(serviceAccount);
    admin.initializeApp({
      credential: admin.credential.cert(credentials as admin.ServiceAccount),
      projectId: config.FIREBASE_PROJECT_ID
    });
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

  if (target.topic) {
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
  if (!twilioClient) {
    return;
  }
  const phoneNumber = payload.target.phoneNumber ?? config.OPS_PHONE;
  if (!phoneNumber) {
    throw new Error("missing phoneNumber for sms channel");
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

async function verifyFirebaseAdmin(req: Request, res: Response, next: Function) {
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

async function verifyUser(req: Request, res: Response, next: Function) {
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
