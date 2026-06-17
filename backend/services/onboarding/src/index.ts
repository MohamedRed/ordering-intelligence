import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import morgan from 'morgan';
import { Storage } from '@google-cloud/storage';
import { Firestore, FieldValue, Timestamp } from '@google-cloud/firestore';
import { PubSub } from '@google-cloud/pubsub';
import { initializeApp, applicationDefault, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { OAuth2Client } from 'google-auth-library';
import twilio from 'twilio';
import Stripe from 'stripe';
import { VertexAI } from '@google-cloud/vertexai';
import fetch from 'node-fetch';
import { registerAgentCreationRoutes } from './agent_creation_routes.js';
import {
  registerDeliveryPartnerStripeRoutes,
  upsertDeliveryPartnerStripeFromAccount,
} from './delivery_partner_stripe.js';
import { registerBusinessProfileRoutes } from './business_profile_routes.js';
import { registerDeliveryPartnerComplianceRoutes } from './delivery_partner_compliance.js';
import { registerMerchantStripeEmbedRoutes } from './merchant_stripe_embed.js';
import { registerFinalizeRoutes } from './finalize_routes.js';
import {
  maskPhone,
  normalizePhoneNumberKey,
  phoneRouteDocIdFromElevenLabsPhoneNumberId,
  phoneRouteDocIdFromToNumber,
} from './phone_routes.js';
import { buildCorsOptions, resolveCorsOrigins } from './cors_policy.js';
import { registerMenuFlyerSessionRoutes } from './menu_flyer_session_routes.js';
import { registerMenuFlyerUploadRoutes } from './menu_flyer_upload.js';
import { registerIngestPubSubRoutes } from './ingest_pubsub_routes.js';
import { registerMenuIngestionRoutes } from './menu_ingestion_routes.js';
import { registerSessionLifecycleRoutes } from './session_lifecycle_routes.js';
import { registerSessionStatusRoutes } from './session_status_routes.js';
import { registerStripeConnectRoutes } from './stripe_connect_routes.js';
import { registerVoiceNumberRoutes } from './voice_number_routes.js';
import {
  createOnboardingAuthMiddleware,
  resolveOnboardingAuthPolicy,
} from './auth_policy.js';
import { resolveOnboardingStripeConfig } from './stripe_config.js';

const app = express();

const PORT = Number(process.env.PORT) || 8080;
const BUCKET = process.env.GCS_BUCKET || 'ordering-intelligence-menus-dev';
const PUBLIC_BASE_URL = process.env.PUBLIC_BASE_URL; // optional override for returned URLs
const MAKE_PUBLIC = (process.env.MAKE_PUBLIC || 'true').toLowerCase() !== 'false';
const STRIPE_CONFIG = resolveOnboardingStripeConfig(process.env);
const STRIPE_SECRET_KEY = STRIPE_CONFIG.secretKey;
const STRIPE_WEBHOOK_SECRET = STRIPE_CONFIG.webhookSecret;
const STRIPE_PUBLISHABLE_KEY = STRIPE_CONFIG.publishableKey;
const stripe = STRIPE_SECRET_KEY
  ? new Stripe(STRIPE_SECRET_KEY, { apiVersion: '2023-10-16' })
  : null;
const firestore = new Firestore();
const SESSIONS = firestore.collection('onboarding_sessions');
const TENANTS = firestore.collection('onboarding_tenants');
const PHONE_NUMBER_ROUTES = firestore.collection('phone_number_routes');
const pubsub = new PubSub();
const MENU_INGEST_TOPIC = process.env.MENU_INGEST_TOPIC || 'menu-ingest';

const TWILIO_ACCOUNT_SID = process.env.TWILIO_ACCOUNT_SID || '';
const TWILIO_AUTH_TOKEN = process.env.TWILIO_AUTH_TOKEN || '';
const TWILIO_NUMBER_POOL = (process.env.TWILIO_NUMBER_POOL || '').split(',').map((s) => s.trim()).filter(Boolean);
const TWILIO_ALLOW_PURCHASE = (process.env.TWILIO_ALLOW_PURCHASE || 'false').toLowerCase() === 'true';
const twilioClient = TWILIO_ACCOUNT_SID && TWILIO_AUTH_TOKEN ? twilio(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN) : null;

const VERTEX_PROJECT = process.env.VERTEX_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || '';
const VERTEX_LOCATION = process.env.VERTEX_LOCATION || 'us-central1';
const PREFILL_MODEL = process.env.PREFILL_MODEL || 'gemini-1.5-flash';
const vertex =
  VERTEX_PROJECT && VERTEX_LOCATION
    ? new VertexAI({ project: VERTEX_PROJECT, location: VERTEX_LOCATION })
    : null;
const MAPS_KEY = process.env.GOOGLE_MAPS_API_KEY || '';
const ENVIRONMENT = (process.env.ENVIRONMENT || process.env.NODE_ENV || '').toLowerCase();
const CORS_ORIGINS = resolveCorsOrigins(process.env.CORS_ORIGINS, ENVIRONMENT || 'development');
const AUTH_POLICY = resolveOnboardingAuthPolicy(process.env);
if ((AUTH_POLICY.requireAuth || AUTH_POLICY.firebaseProjectId) && !getApps().length) {
  initializeApp({
    credential: applicationDefault(),
    projectId: AUTH_POLICY.firebaseProjectId || undefined,
  });
}
const firebaseAuth = getApps().length ? getAuth() : undefined;
const googleOAuth = new OAuth2Client();
const ALLOW_DEMO_SKIP_STRIPE =
  (process.env.ALLOW_DEMO_SKIP_STRIPE || '').toLowerCase() === 'true' ||
  ['dev', 'development', 'local'].includes(ENVIRONMENT);
const DEMO_SKIP_STRIPE_FLAG = 'demo_skip_stripe';

// Optional: used only if we later decide to patch agents via API.
const ELEVENLABS_API_KEY = process.env.ELEVENLABS_API_KEY || '';
const ELEVENLABS_API_BASE_URL = (process.env.ELEVENLABS_API_BASE_URL || 'https://api.elevenlabs.io').replace(/\/+$/, '');
const ELEVENLABS_TEMPLATE_FAST_FOOD_AGENT_ID = process.env.ELEVENLABS_TEMPLATE_FAST_FOOD_AGENT_ID || '';
const ELEVENLABS_TEMPLATE_AUTO_PARTS_AGENT_ID = process.env.ELEVENLABS_TEMPLATE_AUTO_PARTS_AGENT_ID || '';
const ELEVENLABS_TEMPLATE_GAS_STATION_AGENT_ID =
  process.env.ELEVENLABS_TEMPLATE_GAS_STATION_AGENT_ID || '';

async function upsertPhoneNumberRoute(params: {
  onboardingSessionId: string;
  toNumber?: string;
  elevenlabsPhoneNumberId?: string;
  twilioSid?: string;
  tenantId?: string;
  storeId?: string;
  businessType?: string;
  routeStatus?: string;
  source: 'onboarding_voice_number' | 'onboarding_finalize' | 'manual';
}): Promise<void> {
  const ts = Timestamp.now();
  const onboardingSessionId = params.onboardingSessionId.trim();
  const toNumber = params.toNumber ? normalizePhoneNumberKey(params.toNumber) : '';
  const elevenlabsPhoneNumberId = (params.elevenlabsPhoneNumberId || '').trim();

  // Use stable defaults that match finalize() fallback IDs.
  const tenantId = (params.tenantId || '').trim() || `tenant_${onboardingSessionId}`;
  const storeId = (params.storeId || '').trim() || `store_${onboardingSessionId}`;

  const payload: any = {
    route_version: 1,
    source: params.source,
    route_status: params.routeStatus || 'active',
    onboarding_session_id: onboardingSessionId,
    tenant_id: tenantId,
    store_id: storeId,
    business_type: (params.businessType || '').trim(),
    ...(toNumber ? { to_number: toNumber } : {}),
    ...(params.twilioSid ? { twilio_sid: String(params.twilioSid).trim() } : {}),
    ...(elevenlabsPhoneNumberId ? { elevenlabs_phone_number_id: elevenlabsPhoneNumberId } : {}),
    updated_at: ts,
    // Note: we intentionally do not try to keep a perfect created_at without a read.
    created_at: ts,
  };

  const writes: Promise<any>[] = [];
  if (toNumber) {
    writes.push(PHONE_NUMBER_ROUTES.doc(phoneRouteDocIdFromToNumber(toNumber)).set(payload, { merge: true }));
  }
  if (elevenlabsPhoneNumberId) {
    writes.push(
      PHONE_NUMBER_ROUTES.doc(phoneRouteDocIdFromElevenLabsPhoneNumberId(elevenlabsPhoneNumberId)).set(payload, {
        merge: true,
      }),
    );
  }
  if (!writes.length) return;
  await Promise.all(writes);
}

async function elevenlabsJson<T>(path: string, opts: { method: string; body?: any }): Promise<T> {
  if (!ELEVENLABS_API_KEY) throw new Error('ELEVENLABS_API_KEY not configured');
  const url = `${ELEVENLABS_API_BASE_URL}${path}`;
  const res = await fetch(url, {
    method: opts.method,
    headers: {
      'Content-Type': 'application/json',
      'xi-api-key': ELEVENLABS_API_KEY,
    },
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`elevenlabs ${opts.method} ${path} failed status=${res.status} body=${text.slice(0, 400)}`);
  }
  try {
    return JSON.parse(text) as T;
  } catch {
    // Some endpoints can return non-JSON, but our usage expects JSON.
    throw new Error(`elevenlabs ${opts.method} ${path} invalid json: ${text.slice(0, 200)}`);
  }
}

type ElevenLabsPhoneNumber =
  | {
      provider: 'twilio';
      phone_number_id: string;
      phone_number: string;
      label?: string;
      assigned_agent?: { agent_id: string } | null;
    }
  | {
      provider: 'sip_trunk';
      phone_number_id: string;
      phone_number: string;
      label?: string;
      assigned_agent?: { agent_id: string } | null;
    };

async function ensureElevenLabsPhoneNumberImported(params: {
  phoneNumber: string;
  label: string;
  agentId: string;
}): Promise<string> {
  const { phoneNumber, label, agentId } = params;
  // 1) Try find existing
  let existing: ElevenLabsPhoneNumber | undefined;
  try {
    const list = await elevenlabsJson<ElevenLabsPhoneNumber[]>('/v1/convai/phone-numbers', { method: 'GET' });
    existing = list.find((p) => p.phone_number === phoneNumber);
  } catch (err) {
    // If listing fails, still attempt create.
    console.warn('elevenlabs list phone-numbers failed', (err as Error).message);
  }

  const phoneNumberId =
    existing?.phone_number_id ??
    (
      await elevenlabsJson<{ phone_number_id: string }>('/v1/convai/phone-numbers', {
        method: 'POST',
        body: {
          provider: 'twilio',
          phone_number: phoneNumber,
          label,
          sid: TWILIO_ACCOUNT_SID,
          token: TWILIO_AUTH_TOKEN,
          supports_inbound: true,
          supports_outbound: true,
        },
      })
    ).phone_number_id;

  // 2) Assign the (template) agent to the phone number.
  await elevenlabsJson(`/v1/convai/phone-numbers/${encodeURIComponent(phoneNumberId)}`, {
    method: 'PATCH',
    body: { agent_id: agentId },
  });

  return phoneNumberId;
}

type SessionStatus =
  | 'collecting'
  | 'prefill_ready'
  | 'awaiting_kyc'
  | 'ingesting'
  | 'ready'
  | 'failed';

interface OnboardingSession {
  status: SessionStatus;
  business?: {
    name?: string;
    address?: string;
    phone?: string;
    timezone?: string;
    type?: string;
    primaryContact?: string;
    currency?: string;
    fuel_default_prepay_cents?: number;
    fuelDefaultPrepayCents?: number;
  };
  flyers?: string[];
  prefill?: Record<string, any>;
  stripe?: {
    account_id?: string;
    status?: string;
    capabilities?: Record<string, any>;
  };
  twilio?: {
    number?: string;
    sid?: string;
    status?: string;
    elevenlabs_phone_number_id?: string;
  };
  ingestion?: {
    job_ids?: string[];
    status?: string;
    // True once the FastIngestion (menu_only) draft exists, even if image enrichment is later resumed.
    fast_ready?: boolean;
  };
  agent?: {
    template_agent_id?: string;
    business_type?: string;
    mode?: 'shared_template' | 'per_tenant';
    // Backward-compat: older sessions may have a per-tenant agent_id.
    agent_id?: string;
    voice_id?: string;
    branch_id?: string;
    status?: string;
  };
  notifications?: {
    device_tokens?: string[];
    webhook_url?: string;
  };
  audit?: { ts: FirebaseFirestore.Timestamp; actor: string; event: string; data?: any }[];
  tenant?: {
    tenant_id?: string;
    store_id?: string;
  };
  created_at: FirebaseFirestore.Timestamp;
  updated_at: FirebaseFirestore.Timestamp;
}

const storage = new Storage();
const bucket = storage.bucket(BUCKET);

const resolveElevenLabsTemplateAgentId = (businessTypeRaw: string) => {
  const businessType = (businessTypeRaw || '').trim().toLowerCase();
  if (businessType === 'auto_parts') {
    return ELEVENLABS_TEMPLATE_AUTO_PARTS_AGENT_ID || ELEVENLABS_TEMPLATE_FAST_FOOD_AGENT_ID;
  }
  if (businessType === 'gas_station') {
    return ELEVENLABS_TEMPLATE_GAS_STATION_AGENT_ID || ELEVENLABS_TEMPLATE_FAST_FOOD_AGENT_ID;
  }
  return ELEVENLABS_TEMPLATE_FAST_FOOD_AGENT_ID;
};

const jsonParser = express.json();
app.use((req, res, next) => {
  if (req.path === '/stripe/webhook' || req.path === '/ingest-pubsub' || req.path === '/') {
    return next();
  }
  return jsonParser(req, res, next);
});
app.use(morgan('tiny'));
app.use(cors(buildCorsOptions(CORS_ORIGINS)));
app.use(
  createOnboardingAuthMiddleware(AUTH_POLICY, {
    verifyFirebaseToken: (token) => {
      if (!firebaseAuth) throw new Error('firebase_auth_not_configured');
      return firebaseAuth.verifyIdToken(token);
    },
    verifyGoogleIdToken: async (token, audiences) => {
      const ticket = await googleOAuth.verifyIdToken({
        idToken: token,
        audience: audiences,
      });
      return ticket.getPayload() ?? {};
    },
  }),
);

registerDeliveryPartnerStripeRoutes({
  app,
  firestore,
  stripe,
  publicBaseUrl: PUBLIC_BASE_URL,
  stripePublishableKey: STRIPE_PUBLISHABLE_KEY,
});
registerDeliveryPartnerComplianceRoutes({
  app,
  firestore,
  bucket,
  publicBaseUrl: PUBLIC_BASE_URL,
  makePublic: MAKE_PUBLIC,
});
registerMerchantStripeEmbedRoutes({
  app,
  firestore,
  stripe,
  publicBaseUrl: PUBLIC_BASE_URL,
  stripePublishableKey: STRIPE_PUBLISHABLE_KEY,
});
registerMenuFlyerUploadRoutes({
  app,
  bucket,
  publicBaseUrl: PUBLIC_BASE_URL,
  makePublic: MAKE_PUBLIC,
});

// Utility: audit log append
const audit = async (id: string, event: string, data?: any) => {
  const ts = Timestamp.now();
  const entry: any = { ts, actor: 'system', event };
  if (data !== undefined) entry.data = data;
  await SESSIONS.doc(id).update({
    audit: FieldValue.arrayUnion(entry),
    updated_at: ts,
  });
};

// Utility: fetch session or 404
const getSession = async (id: string, res: express.Response) => {
  const snap = await SESSIONS.doc(id).get();
  if (!snap.exists) {
    res.status(404).json({ error: 'session_not_found' });
    return null;
  }
  return { id, ...(snap.data() as OnboardingSession) };
};

registerMenuIngestionRoutes({
  app,
  firestore,
  sessions: SESSIONS,
  pubsub,
  bucket,
  bucketName: BUCKET,
  menuIngestTopic: MENU_INGEST_TOPIC,
  getSession,
  audit,
});
registerMenuFlyerSessionRoutes({
  app,
  sessions: SESSIONS,
  getSession,
  audit,
});
registerBusinessProfileRoutes({
  app,
  sessions: SESSIONS,
  vertex,
  prefillModel: PREFILL_MODEL,
  getSession,
  audit,
});
registerVoiceNumberRoutes({
  app,
  sessions: SESSIONS,
  twilioClient,
  twilioNumberPool: TWILIO_NUMBER_POOL,
  twilioAllowPurchase: TWILIO_ALLOW_PURCHASE,
  elevenLabsEnabled: Boolean(ELEVENLABS_API_KEY && TWILIO_ACCOUNT_SID && TWILIO_AUTH_TOKEN),
  resolveTemplateAgentId: resolveElevenLabsTemplateAgentId,
  importElevenLabsPhoneNumber: ensureElevenLabsPhoneNumberImported,
  upsertPhoneNumberRoute,
  maskPhone,
  getSession,
  audit,
});
registerAgentCreationRoutes({
  app,
  firestore,
  sessions: SESSIONS,
  getSession,
  audit,
  resolveTemplateAgentId: resolveElevenLabsTemplateAgentId,
});
registerSessionStatusRoutes({
  app,
  firestore,
  sessions: SESSIONS,
  getSession,
  audit,
});
registerIngestPubSubRoutes({
  app,
  sessions: SESSIONS,
  getSession,
  audit,
});
registerSessionLifecycleRoutes({
  app,
  sessions: SESSIONS,
  tenants: TENANTS,
  getSession,
  audit,
});
registerStripeConnectRoutes({
  app,
  firestore,
  sessions: SESSIONS,
  stripe,
  stripeWebhookSecret: STRIPE_WEBHOOK_SECRET,
  mapsKey: MAPS_KEY,
  fetchImpl: fetch,
  getSession,
  audit,
  upsertDeliveryPartnerStripeFromAccount,
});
registerFinalizeRoutes({
  app,
  firestore,
  sessions: SESSIONS,
  onboardingTenants: TENANTS,
  allowDemoSkipStripe: ALLOW_DEMO_SKIP_STRIPE,
  demoSkipStripeFlag: DEMO_SKIP_STRIPE_FLAG,
  getSession,
  audit,
  upsertPhoneNumberRoute,
  maskPhone,
});

app.get('/healthz', (_req, res) => {
  res.json({ status: 'ok' });
});

// 2) Stripe endpoints (already defined below) are part of flow

app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error(err);
  res.status(500).json({ error: 'internal_error', message: err.message });
});

app.listen(PORT, () => {
  console.log(`Onboarding service listening on :${PORT}`);
});
