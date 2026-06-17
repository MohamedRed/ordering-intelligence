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
import bodyParser from 'body-parser';
import twilio from 'twilio';
import { v4 as uuidv4 } from 'uuid';
import Stripe from 'stripe';
import { VertexAI } from '@google-cloud/vertexai';
import fetch from 'node-fetch';
import {
  registerDeliveryPartnerStripeRoutes,
  upsertDeliveryPartnerStripeFromAccount,
} from './delivery_partner_stripe.js';
import { registerDeliveryPartnerComplianceRoutes } from './delivery_partner_compliance.js';
import { registerMerchantStripeEmbedRoutes } from './merchant_stripe_embed.js';
import {
  maskPhone,
  normalizePhoneNumberKey,
  phoneRouteDocIdFromElevenLabsPhoneNumberId,
  phoneRouteDocIdFromToNumber,
} from './phone_routes.js';
import { buildCorsOptions, resolveCorsOrigins } from './cors_policy.js';
import { registerMenuFlyerSessionRoutes } from './menu_flyer_session_routes.js';
import { registerMenuFlyerUploadRoutes } from './menu_flyer_upload.js';
import { registerMenuIngestionRoutes } from './menu_ingestion_routes.js';
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

interface OnboardingTenantState {
  active_session_id?: string;
  last_session_id?: string;
  store_id?: string;
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
// Dedicated raw parser for Pub/Sub push (accept any content-type)
const pubsubRaw = bodyParser.raw({ type: '*/*' });

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

// Geocode + timezone from address/country
const geocodeTimezone = async (address?: string, country?: string) => {
  if (!address || !MAPS_KEY) return {};
  const encoded = encodeURIComponent(address + (country ? ` ${country}` : ''));
  const geoUrl = `https://maps.googleapis.com/maps/api/geocode/json?address=${encoded}&key=${MAPS_KEY}`;
  const geoResp = await fetch(geoUrl);
  if (!geoResp.ok) return {};
  const geo: any = await geoResp.json();
  const result = geo.results?.[0];
  if (!result) return {};
  const loc = result.geometry?.location;
  const lat = loc?.lat;
  const lng = loc?.lng;
  if (lat == null || lng == null) return { address: result.formatted_address };
  const tzUrl = `https://maps.googleapis.com/maps/api/timezone/json?location=${lat},${lng}&timestamp=${Math.floor(
    Date.now() / 1000,
  )}&key=${MAPS_KEY}`;
  const tzResp = await fetch(tzUrl);
  let timezone: string | undefined;
  if (tzResp.ok) {
    const tz: any = await tzResp.json();
    if (tz.status === 'OK') timezone = tz.timeZoneId;
  }
  return {
    address: result.formatted_address as string,
    lat,
    lng,
    timezone,
  };
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

app.get('/healthz', (_req, res) => {
  res.json({ status: 'ok' });
});

// Tenant onboarding state (resume support)
app.get('/onboarding-tenants/:tenantId', async (req, res) => {
  try {
    const tenantId = (req.params.tenantId || '').trim();
    if (!tenantId) return res.status(400).json({ error: 'tenant_id_required' });

    const tenantSnap = await TENANTS.doc(tenantId).get();
    if (!tenantSnap.exists) {
      return res.status(404).json({ error: 'tenant_not_found' });
    }
    const tenantState = tenantSnap.data() as OnboardingTenantState;
    const activeId = tenantState.active_session_id;
    let session: any = null;
    if (activeId) {
      const s = await SESSIONS.doc(activeId).get();
      if (s.exists) {
        session = { session_id: activeId, ...(s.data() as OnboardingSession) };
      }
    }
    res.json({
      tenant_id: tenantId,
      active_session_id: activeId ?? null,
      last_session_id: tenantState.last_session_id ?? null,
      store_id: tenantState.store_id ?? null,
      session,
    });
  } catch (err: any) {
    console.error('tenant status error', err);
    res.status(500).json({ error: 'tenant_status_failed', message: err.message });
  }
});

// 1) Start session
app.post('/onboarding-sessions', async (req, res) => {
  try {
    const tenantId = (req.body?.tenant_id as string | undefined)?.trim();
    const storeId = (req.body?.store_id as string | undefined)?.trim();

    if (tenantId) {
      const tenantDocRef = TENANTS.doc(tenantId);
      const tenantSnap = await tenantDocRef.get();
      const tenantState = (tenantSnap.exists ? (tenantSnap.data() as OnboardingTenantState) : null) ?? null;
      const activeId = tenantState?.active_session_id;
      if (activeId) {
        const activeSnap = await SESSIONS.doc(activeId).get();
        if (activeSnap.exists) {
          const active = activeSnap.data() as OnboardingSession;
          if (active.status !== 'ready' && active.status !== 'failed') {
            return res.status(201).json({ session_id: activeId, reused: true });
          }
        }
      }
    }

    const id = uuidv4();
    const now = Timestamp.now();
    const doc: OnboardingSession = {
      status: 'collecting',
      business: {},
      flyers: [],
      audit: [],
      tenant: tenantId ? { tenant_id: tenantId, store_id: storeId } : undefined,
      created_at: now,
      updated_at: now,
    };
    await SESSIONS.doc(id).set(doc);
    await audit(id, 'session_created', tenantId ? { tenant_id: tenantId, store_id: storeId } : undefined);

    if (tenantId) {
      const tenantDoc: OnboardingTenantState = {
        active_session_id: id,
        last_session_id: id,
        store_id: storeId,
        created_at: now,
        updated_at: now,
      };
      await TENANTS.doc(tenantId).set(tenantDoc, { merge: true });
    }

    res.status(201).json({ session_id: id, reused: false });
  } catch (err: any) {
    console.error('create session error', err);
    res.status(500).json({ error: 'session_create_failed', message: err.message });
  }
});

// 2) AI prefill from menu flyers
app.post('/onboarding-sessions/:id/prefill', async (req, res) => {
  try {
    const { id } = req.params;
    const snap = await getSession(id, res);
    if (!snap) return;
    if (!vertex) return res.status(500).json({ error: 'vertex_not_configured' });
    const flyers = snap.flyers ?? [];
    if (flyers.length === 0) return res.status(400).json({ error: 'no_flyers' });

    const prompt = `
You are extracting business profile and menu hints from image URLs (flyers).
Return compact JSON with keys: business_name, address, phone, hours (string), categories (array of strings), notes.
Keep null when unknown. Do not include any extra fields.
Flyer URLs:
${flyers.join('\n')}
`;

    const model = vertex.getGenerativeModel({ model: PREFILL_MODEL });
    const result = await model.generateContent({
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: { temperature: 0.2, maxOutputTokens: 512 },
    });
    const text = result.response.candidates?.[0]?.content?.parts?.map((p) => p.text).join(' ') || '';
    let parsed: any = { raw: text };
    try {
      const jsonMatch = text.match(/\\{[\\s\\S]*\\}/);
      if (jsonMatch) parsed = JSON.parse(jsonMatch[0]);
    } catch (_e) {
      // fallback to raw text
    }
    const prefill = { model: PREFILL_MODEL, raw: text, parsed };
    const ts = Timestamp.now();
    await SESSIONS.doc(id).update({ prefill, status: 'prefill_ready', updated_at: ts });
    await audit(id, 'prefill_generated');
    res.json({ prefill });
  } catch (err: any) {
    console.error('prefill error', err);
    res.status(500).json({ error: 'prefill_failed', message: err.message });
  }
});

// 4) Business details
app.patch('/onboarding-sessions/:id/business-details', async (req, res) => {
  try {
    const { id } = req.params;
    const snap = await getSession(id, res);
    if (!snap) return;
    const ts = Timestamp.now();
    await SESSIONS.doc(id).update({ business: req.body, updated_at: ts });
    await audit(id, 'business_updated', req.body);
    res.json({ ok: true });
  } catch (err: any) {
    console.error('business-details error', err);
    res.status(500).json({ error: 'business_update_failed', message: err.message });
  }
});

// 5) Stripe endpoints (already defined below) are part of flow

// 6) Voice number provisioning
app.post('/onboarding-sessions/:id/voice-number', async (req, res) => {
  try {
    const { id } = req.params;
    const snap = await getSession(id, res);
    if (!snap) return;

    if (!twilioClient) return res.status(500).json({ error: 'twilio_not_configured' });
    let number = req.body?.number as string | undefined;
    let twilioSid: string | undefined;

    if (!number) {
      // If a pool is provided, pick first; otherwise attempt to buy a new number (US).
      if (TWILIO_NUMBER_POOL.length > 0) {
        number = TWILIO_NUMBER_POOL[0];
      } else {
        if (!TWILIO_ALLOW_PURCHASE) {
          return res.status(400).json({ error: 'no_pool_and_purchase_disabled' });
        }
        const search = await twilioClient.availablePhoneNumbers('US').local.list({ areaCode: 415, limit: 1 });
        if (!search.length) return res.status(500).json({ error: 'no_numbers_available' });
        const purchased = await twilioClient.incomingPhoneNumbers.create({ phoneNumber: search[0].phoneNumber });
        number = purchased.phoneNumber;
        twilioSid = purchased.sid;
        const ts = Timestamp.now();
        await SESSIONS.doc(id).update({
          twilio: { number, sid: purchased.sid, status: 'assigned' },
          updated_at: ts,
        });
        await audit(id, 'twilio_assigned', { number, sid: purchased.sid, source: 'purchased' });
        // continue below to optionally import into ElevenLabs
      }
    }

    // For pool or provided number, try to look up SID
    if (!twilioSid) {
      const lookup = await twilioClient.incomingPhoneNumbers.list({ phoneNumber: number, limit: 1 });
      twilioSid = lookup[0]?.sid;
    }
    const ts = Timestamp.now();
    await SESSIONS.doc(id).update({ twilio: { number, sid: twilioSid, status: 'assigned' }, updated_at: ts });
    await audit(id, 'twilio_assigned', {
      number,
      sid: twilioSid,
      source: twilioSid ? 'existing' : 'pool_without_sid',
    });

    // Optional: import the phone number into ElevenLabs and assign the template agent.
    // This enables ElevenLabs Twilio integration to route calls on this number to the selected agent.
    let elevenlabs_phone_number_id: string | undefined;
    if (ELEVENLABS_API_KEY && TWILIO_ACCOUNT_SID && TWILIO_AUTH_TOKEN) {
      try {
        const businessType = ((snap.business?.type || '').trim() || 'fast_food').toLowerCase();
        const agentId =
          (snap.agent?.template_agent_id || '').trim() || resolveElevenLabsTemplateAgentId(businessType);
        if (agentId) {
          const label = `${(snap.business?.name || 'Business').slice(0, 40)} (${businessType})`;
          elevenlabs_phone_number_id = await ensureElevenLabsPhoneNumberImported({
            phoneNumber: number,
            label,
            agentId,
          });
          await SESSIONS.doc(id).update({
            twilio: {
              number,
              sid: twilioSid,
              status: 'assigned',
              elevenlabs_phone_number_id,
            },
            updated_at: Timestamp.now(),
          });
          await audit(id, 'elevenlabs_phone_number_imported', {
            phone_number_id: elevenlabs_phone_number_id,
            phone_number: maskPhone(number),
            agent_id: agentId,
          });
        }
      } catch (err: any) {
        console.error('elevenlabs phone import failed', err?.message ?? err);
        await audit(id, 'elevenlabs_phone_number_import_failed', { message: err?.message ?? String(err) });
      }
    }

    // Durable routing mapping: written immediately on assignment so webhook routing doesn't depend on onboarding state.
    try {
      await upsertPhoneNumberRoute({
        onboardingSessionId: id,
        toNumber: number,
        elevenlabsPhoneNumberId: elevenlabs_phone_number_id,
        twilioSid,
        tenantId: snap.tenant?.tenant_id || '',
        storeId: snap.tenant?.store_id || '',
        businessType: snap.business?.type || '',
        routeStatus: snap.status || 'active',
        source: 'onboarding_voice_number',
      });
      await audit(id, 'phone_number_route_upserted', {
        to_number: maskPhone(number),
        phone_number_id: elevenlabs_phone_number_id || null,
      });
    } catch (err: any) {
      console.error('phone_number_routes upsert failed', err?.message ?? err);
      await audit(id, 'phone_number_route_upsert_failed', { message: err?.message ?? String(err) });
    }

    res.json({ number, sid: twilioSid, elevenlabs_phone_number_id });
  } catch (err: any) {
    console.error('voice-number error', err);
    res.status(500).json({ error: 'voice_number_failed', message: err.message });
  }
});

// 7) Create ElevenLabs agent (duplicate a template based on business type)
app.post('/onboarding-sessions/:id/create-agent', async (req, res) => {
  try {
    const { id } = req.params;
    const snap = await getSession(id, res);
    if (!snap) return;

    // Idempotent: return existing agent config if already set.
    const existingAgentId = (snap as any).agent?.agent_id as string | undefined;
    const existingTemplateId = (snap as any).agent?.template_agent_id as string | undefined;
    if (existingTemplateId || existingAgentId) {
      return res.json({
        reused: true,
        agent_mode: existingTemplateId ? 'shared_template' : 'per_tenant',
        template_agent_id: existingTemplateId ?? null,
        agent_id: existingTemplateId ?? existingAgentId,
      });
    }

    const ingestStatus = (snap.ingestion?.status || '').toLowerCase();
    const fastReadyFromSession = !!snap.ingestion?.fast_ready;
    const readyByStatus = ['succeeded', 'partial_ok'].includes(ingestStatus);
    let ready = readyByStatus || fastReadyFromSession;

    // If image enrichment is running, the session status may be queued/processing; allow agent creation as long as
    // the FastIngestion draft exists (menus_drafts/{jobId}) or the job has a readyKind from a prior run.
    if (!ready) {
      const jobIds = snap.ingestion?.job_ids || [];
      const jobId = jobIds.length ? jobIds[jobIds.length - 1] : null;
      if (jobId) {
        try {
          const jobSnap = await firestore.collection('menus_ingest').doc(jobId).get();
          const job = jobSnap.exists ? (jobSnap.data() as any) : null;
          const kind = (job?.readyKind ?? '').toLowerCase();
          if (kind === 'menu_only' || kind === 'full') ready = true;
        } catch (_) {
          // ignore
        }
        if (!ready) {
          try {
            const draftSnap = await firestore.collection('menus_drafts').doc(jobId).get();
            if (draftSnap.exists) ready = true;
          } catch (_) {
            // ignore
          }
        }
      }
    }

    if (!ready) {
      return res.status(400).json({ error: 'ingestion_not_ready', status: snap.ingestion?.status || null });
    }

    const businessType = ((snap.business?.type || '').trim() || 'fast_food').toLowerCase();
    const templateAgentId = resolveElevenLabsTemplateAgentId(businessType);
    if (!templateAgentId) {
      return res.status(500).json({ error: 'elevenlabs_template_not_configured', business_type: businessType });
    }

    const ts = Timestamp.now();
    await SESSIONS.doc(id).update({
      agent: {
        mode: 'shared_template',
        template_agent_id: templateAgentId,
        business_type: businessType,
        status: 'configured',
      },
      updated_at: ts,
    });
    await audit(id, 'agent_created', {
      template_agent_id: templateAgentId,
      business_type: businessType,
      mode: 'shared_template',
    });
    // Backward compat: return agent_id for the UI, but in shared-template mode it's the template id.
    res.json({
      reused: false,
      agent_mode: 'shared_template',
      template_agent_id: templateAgentId,
      agent_id: templateAgentId,
    });
  } catch (err: any) {
    console.error('create-agent error', err);
    res.status(500).json({ error: 'agent_create_failed', message: err.message });
  }
});

// Pub/Sub push handler for ingestion completion events
// Expects message.data base64 JSON: { session_id?, job_id?, status }
const handleIngestPubSub = async (req: express.Request, res: express.Response) => {
  try {
    let body: any = (req as any).body;
    if (Buffer.isBuffer(body)) {
      try {
        body = JSON.parse(body.toString('utf8'));
      } catch {
        body = undefined;
      }
    } else if (typeof body === 'string') {
      try {
        body = JSON.parse(body);
      } catch {
        body = undefined;
      }
    }
    const msg: any = body?.message;
    if (!msg?.data) return res.status(400).json({ error: 'invalid_message' });

    const decoded = JSON.parse(Buffer.from(msg.data, 'base64').toString('utf8'));
    const jobId = decoded.job_id || decoded.jobId;
    const status = decoded.status as string | undefined;
    let sessionId = decoded.session_id as string | undefined;

    console.log('ingest-pubsub received', { jobId, status, sessionId });

    if (!status) return res.status(400).json({ error: 'status_required' });

    // If session_id missing, try lookup by job id
    if (!sessionId && jobId) {
      const snap = await SESSIONS.where('ingestion.job_ids', 'array-contains', jobId).limit(1).get();
      if (!snap.empty) sessionId = snap.docs[0].id;
    }
    if (!sessionId) return res.status(400).json({ error: 'session_id_not_found' });

    const snap = await getSession(sessionId, res);
    if (!snap) return;

    const ts = Timestamp.now();
    const normalized =
      status === 'completed' || status === 'succeeded' ? 'succeeded' :
      status === 'partial_ok' ? 'partial_ok' :
      status === 'error' || status === 'failed' ? 'error' :
      status;

    const updates: any = {
      ingestion: {
        job_ids: snap.ingestion?.job_ids ?? (jobId ? [jobId] : []),
        status: normalized,
      },
      updated_at: ts,
    };
    // Optionally advance overall session status when ingestion completes
    if (normalized === 'succeeded' && snap.status === 'ingesting') {
      updates.status = 'ready';
    }

    await SESSIONS.doc(sessionId).update(updates);
    await audit(sessionId, 'ingest_pubsub', { job_id: jobId, status: normalized });
    res.status(204).send();
  } catch (err: any) {
    console.error('ingest-pubsub error', err);
    res.status(500).json({ error: 'ingest_pubsub_failed', message: err.message });
  }
};

// Accept Pub/Sub push on both /ingest-pubsub and /
app.all(['/ingest-pubsub', '/'], (req, res) => {
  if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');
  pubsubRaw(req, res, (err) => {
    if (err) {
      console.error('ingest-pubsub parse error', err);
      return res.status(400).json({ error: 'invalid_json', message: err.message });
    }
    return handleIngestPubSub(req, res);
  });
});

// 8) Notification preferences
app.post('/onboarding-sessions/:id/notifications', async (req, res) => {
  try {
    const { id } = req.params;
    const { device_tokens = [], webhook_url } = req.body || {};
    const snap = await getSession(id, res);
    if (!snap) return;
    const ts = Timestamp.now();
    await SESSIONS.doc(id).update({
      notifications: {
        device_tokens,
        webhook_url,
      },
      updated_at: ts,
    });
    await audit(id, 'notifications_set', { device_tokens, webhook_url });
    res.json({ ok: true });
  } catch (err: any) {
    console.error('notifications error', err);
    res.status(500).json({ error: 'notifications_failed', message: err.message });
  }
});

// 9) Finalize tenant (creates tenant/store drafts)
app.post('/onboarding-sessions/:id/finalize', async (req, res) => {
  try {
    const { id } = req.params;
    const snap = await getSession(id, res);
    if (!snap) return;
    // Readiness gate
    const missing: string[] = [];
    if (!snap.business?.name) missing.push('business.name');
    if (!snap.flyers || snap.flyers.length === 0) missing.push('flyers');
    if (!snap.twilio?.number) missing.push('twilio.number');
    const tenantIdForFlags = (snap.tenant?.tenant_id || '').trim();
    let demoSkipStripe = false;
    if (ALLOW_DEMO_SKIP_STRIPE && tenantIdForFlags) {
      try {
        const tSnap = await firestore.collection('tenants').doc(tenantIdForFlags).get();
        const flags = (tSnap.data() as any)?.featureFlags as Record<string, any> | undefined;
        if (flags?.[DEMO_SKIP_STRIPE_FLAG] === true) {
          demoSkipStripe = true;
        }
      } catch (err) {
        // Best-effort; ignore and treat as not enabled.
        console.warn('demo_skip_stripe flag read failed', err);
      }
    }
    const stripeStatus = snap.stripe?.status || '';
    if (!demoSkipStripe) {
      if (!['active', 'pending_review', 'requirements_due', 'pending'].includes(stripeStatus)) {
        missing.push('stripe_kyc');
      }
    }
    const ingestStatus = snap.ingestion?.status || '';
    if (!['succeeded', 'partial_ok'].includes(ingestStatus)) {
      missing.push('ingestion');
    }
    if (!snap.agent?.template_agent_id && !snap.agent?.agent_id) {
      missing.push('agent');
    }
    if (missing.length) {
      return res.status(400).json({ error: 'not_ready', missing });
    }

    // Create tenant/store drafts
    const tenantsCol = firestore.collection('tenants');
    const storesCol = firestore.collection('stores');
    const tenantId = snap.tenant?.tenant_id || `tenant_${id}`;
    const storeId = snap.tenant?.store_id || `store_${id}`;
    const ts = Timestamp.now();

  const tenantPayload = {
    name: snap.business?.name || 'Unnamed',
    phone: snap.business?.phone || '',
    address: snap.business?.address || '',
    timezone: snap.business?.timezone || '',
    stripe_account_id: snap.stripe?.account_id || '',
    status: 'ready',
    created_at: ts,
    updated_at: ts,
  };

	  const storePayload = {
	    store_id: storeId,
	    tenant_id: tenantId,
	    business_type: snap.business?.type || '',
	    currency: snap.business?.currency || '',
	    fuel_default_prepay_cents: snap.business?.fuel_default_prepay_cents || snap.business?.fuelDefaultPrepayCents || 0,
	    menu_job_ids: snap.ingestion?.job_ids || [],
	    elevenlabs_agent_template_id: snap.agent?.template_agent_id || '',
	    elevenlabs_agent_mode: snap.agent?.template_agent_id ? 'shared_template' : (snap.agent?.agent_id ? 'per_tenant' : ''),
	    // Backward compat: keep the older field if a per-tenant agent exists.
	    ...(snap.agent?.agent_id ? { elevenlabs_agent_id: snap.agent?.agent_id || '' } : {}),
	    elevenlabs_voice_id: snap.agent?.voice_id || '',
	    elevenlabs_agent_branch_id: snap.agent?.branch_id || '',
	    // Suggested runtime variables for ElevenLabs dynamic variables / tool path params.
	    elevenlabs_variables: {
	      tenantId,
	      storeId,
	      businessType: (snap.business?.type || '').trim(),
	    },
	    twilio_number: snap.twilio?.number || '',
	    elevenlabs_phone_number_id: snap.twilio?.elevenlabs_phone_number_id || '',
	    // Default order comms config (safe defaults: no customer comms until enabled).
	    order_comms: {
	      default_wait_minutes: 15,
	      statuses: {
	        pending: { default_channel: 'none', default_template_id: 'default', templates: [{ id: 'default', label: 'Default', body: 'Your order was received.' }] },
	        confirmed: { default_channel: 'none', default_template_id: 'default', templates: [{ id: 'default', label: 'Default', body: 'Your order has been confirmed.' }] },
	        ready: { default_channel: 'none', default_template_id: 'default', templates: [{ id: 'default', label: 'Default', body: 'Your order is ready for pickup.' }] },
	        completed: { default_channel: 'none', default_template_id: 'default', templates: [{ id: 'default', label: 'Default', body: 'Thanks — your order is marked completed.' }] },
	        cancelled: { default_channel: 'none', default_template_id: 'default', templates: [{ id: 'default', label: 'Default', body: 'Your order was cancelled. Please contact the store if you have questions.' }] },
	        delay: { default_channel: 'none', default_template_id: 'default', templates: [{ id: 'default', label: 'Default', body: 'Your order is running a bit late.' }] },
	      },
	      ready_escalation_enabled: false,
	      ready_escalation_minutes: 5,
	      ready_escalation_channel: 'call',
	    },
	    created_at: ts,
	    updated_at: ts,
	  };

    await tenantsCol.doc(tenantId).set(tenantPayload, { merge: true });
    await storesCol.doc(storeId).set(storePayload, { merge: true });

    // Update durable routing mapping with finalized tenant/store IDs (so runtime webhooks can route without onboarding state).
    try {
      await upsertPhoneNumberRoute({
        onboardingSessionId: id,
        toNumber: snap.twilio?.number || '',
        elevenlabsPhoneNumberId: snap.twilio?.elevenlabs_phone_number_id || '',
        twilioSid: snap.twilio?.sid || '',
        tenantId,
        storeId,
        businessType: snap.business?.type || '',
        routeStatus: 'ready',
        source: 'onboarding_finalize',
      });
      await audit(id, 'phone_number_route_finalized', {
        tenant_id: tenantId,
        store_id: storeId,
        to_number: maskPhone(snap.twilio?.number || ''),
      });
    } catch (err: any) {
      console.error('phone_number_routes finalize upsert failed', err?.message ?? err);
      await audit(id, 'phone_number_route_finalize_failed', { message: err?.message ?? String(err) });
    }

    await SESSIONS.doc(id).update({ status: 'ready', tenant: { tenant_id: tenantId, store_id: storeId }, updated_at: ts });
    const auditPayload: Record<string, any> = {
      tenant_id: tenantId,
      store_id: storeId,
    };
    if (demoSkipStripe) {
      auditPayload.demo_skip_stripe = true;
    }
    await audit(id, 'finalized', auditPayload);
    // Mark tenant onboarding session as completed (so a new one can be created later).
    if (tenantId) {
      await TENANTS.doc(tenantId).set(
        {
          active_session_id: FieldValue.delete(),
          last_session_id: id,
          store_id: storeId,
          updated_at: ts,
        } as any,
        { merge: true },
      );
    }
    res.json({ status: 'ready', tenant_id: tenantId, store_id: storeId });
  } catch (err: any) {
    console.error('finalize error', err);
    res.status(500).json({ error: 'finalize_failed', message: err.message });
  }
});

// 10) Status & audit
app.get('/onboarding-sessions/:id/status', async (req, res) => {
  const snap = await getSession(req.params.id, res);
  if (!snap) return;
  res.json({ status: snap.status, ingestion: snap.ingestion, stripe: snap.stripe, twilio: snap.twilio, agent: snap.agent });
});

app.get('/onboarding-sessions/:id/audit', async (req, res) => {
  const snap = await getSession(req.params.id, res);
  if (!snap) return;
  res.json({ audit: snap.audit ?? [] });
});

// Sync ingestion status from menus_ingest collection (utility endpoint)
app.post('/onboarding-sessions/:id/sync-ingest', async (req, res) => {
  try {
    const { id } = req.params;
    const snap = await getSession(id, res);
    if (!snap) return;
    const jobIds = snap.ingestion?.job_ids || [];
    if (!jobIds.length) return res.json({ status: 'not_started', progress: { percent: 0, stage: 'not_started' } });

    const jobsSnap = await firestore.getAll(
      ...jobIds.map((jid) => firestore.collection('menus_ingest').doc(jid)),
    );
    let status = snap.ingestion?.status || 'unknown';
    let fastReady = !!snap.ingestion?.fast_ready;
    let bestPercent = 0;
    let bestStage: string | undefined;
    for (const j of jobsSnap) {
      if (!j.exists) continue;
      const data = j.data() as any;
      const pct = typeof data.progressPercent === 'number' ? data.progressPercent : undefined;
      const stage = typeof data.progressStage === 'string' ? data.progressStage : undefined;
      const readyKind = typeof data.readyKind === 'string' ? data.readyKind : undefined;
      if (readyKind && ['menu_only', 'full'].includes(readyKind.toLowerCase())) {
        fastReady = true;
      }
      if (pct != null && pct >= bestPercent) {
        bestPercent = pct;
        bestStage = stage;
      }
      // take the most critical status
      if (data.status === 'canceled') { status = 'canceled'; break; }
      if (data.status === 'error') { status = 'error'; break; }
      if (data.status === 'processing') status = 'processing';
      if (data.status === 'queued' && status !== 'processing') status = 'queued';
      if (data.status === 'uploading' && status !== 'processing') status = 'queued';
      if (data.status === 'ready') status = 'succeeded';
      if (data.status === 'completed' || data.status === 'succeeded') status = 'succeeded';
      if (data.status === 'ready' || data.status === 'completed' || data.status === 'succeeded') fastReady = true;
    }

    if (!bestStage) {
      bestStage =
        status === 'succeeded' ? 'done' :
        status === 'processing' ? 'processing' :
        status === 'queued' ? 'queued' :
        status === 'canceled' ? 'canceled' :
        status === 'error' ? 'error' :
        status;
    }
    if (status === 'succeeded') bestPercent = 100;
    if (status === 'error' && bestPercent < 100) bestPercent = 100;
    if (status === 'canceled' && bestPercent < 100) bestPercent = 100;

    const ts = Timestamp.now();
    await SESSIONS.doc(id).update({ ingestion: { job_ids: jobIds, status, fast_ready: fastReady }, updated_at: ts });
    await audit(id, 'ingest_synced', { status, fast_ready: fastReady });
    res.json({ status, fast_ready: fastReady, progress: { percent: bestPercent, stage: bestStage } });
  } catch (err: any) {
    console.error('sync-ingest error', err);
    res.status(500).json({ error: 'sync_ingest_failed', message: err.message });
  }
});

// Fetch per-AI-call workflow nodes for the current ingestion job.
// Useful for a DAG visualization in the admin UI.
app.get('/onboarding-sessions/:id/ingest-workflow', async (req, res) => {
  try {
    const { id } = req.params;
    const snap = await getSession(id, res);
    if (!snap) return;
    const jobIds = snap.ingestion?.job_ids || [];
    if (!jobIds.length) return res.json({ job_id: null, nodes: [] });

    const requested = (req.query.job_id as string | undefined)?.trim();
    const jobId = (requested && jobIds.includes(requested) ? requested : jobIds[0]) as string;
    const limitRaw = Number(req.query.limit ?? 600);
    const limit = Number.isFinite(limitRaw) ? Math.max(1, Math.min(2000, limitRaw)) : 600;

    const nodesSnap = await firestore
      .collection('menus_ingest')
      .doc(jobId)
      .collection('workflow_nodes')
      .limit(limit)
      .get();
    const nodes = nodesSnap.docs.map((d) => d.data());
    nodes.sort((a: any, b: any) => {
      const sa = typeof a.seq === 'number' ? a.seq : Number.MAX_SAFE_INTEGER;
      const sb = typeof b.seq === 'number' ? b.seq : Number.MAX_SAFE_INTEGER;
      if (sa !== sb) return sa - sb;
      const ta = typeof a.startedAt === 'number' ? a.startedAt : 0;
      const tb = typeof b.startedAt === 'number' ? b.startedAt : 0;
      return ta - tb;
    });
    res.json({ job_id: jobId, nodes });
  } catch (err: any) {
    console.error('ingest-workflow error', err);
    res.status(500).json({ error: 'ingest_workflow_failed', message: err.message });
  }
});

app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error(err);
  res.status(500).json({ error: 'internal_error', message: err.message });
});

// ---- Stripe Connect (embedded onboarding) via SDK ----

app.post('/stripe/account', async (req, res) => {
  if (!stripe) return res.status(500).json({ error: 'stripe_not_configured' });
  try {
    const { session_id, capabilities = ['card_payments', 'transfers'], business_type = 'company' } = req.body || {};
    if (!session_id) return res.status(400).json({ error: 'session_id_required' });
    const session = await getSession(session_id, res);
    if (!session) return;
    const account = await stripe.accounts.create({
      type: 'custom',
      country: 'US',
      business_type,
      capabilities: Object.fromEntries(capabilities.map((c: string) => [c, { requested: true }])),
      settings: { payouts: { schedule: { interval: 'manual' } } },
    });
    const ts = Timestamp.now();
    await SESSIONS.doc(session_id).update({
      stripe: {
        account_id: account.id,
        status: account.requirements?.disabled_reason ?? 'pending',
        capabilities: account.capabilities ?? {},
      },
      updated_at: ts,
    });
    await audit(session_id, 'stripe_account_created', { account_id: account.id });
    res.status(201).json({ account_id: account.id, capabilities });
  } catch (err: any) {
    console.error('stripe account error', err);
    res.status(500).json({ error: 'stripe_account_failed', message: err.message });
  }
});

app.post('/stripe/account-session', async (req, res) => {
  if (!stripe) return res.status(500).json({ error: 'stripe_not_configured' });
  try {
    const { session_id } = req.body || {};
    if (!session_id) return res.status(400).json({ error: 'session_id_required' });
    const sessionDoc = await getSession(session_id, res);
    if (!sessionDoc) return;
    const account_id = sessionDoc.stripe?.account_id;
    if (!account_id) return res.status(400).json({ error: 'account_id_missing_for_session' });
    const stripeSession = await stripe.accountSessions.create({
      account: account_id,
      components: {
        account_onboarding: { enabled: true },
        payouts: { enabled: true },
      },
    });
    res.status(201).json({ client_secret: stripeSession.client_secret });
  } catch (err: any) {
    console.error('stripe account-session error', err);
    res.status(500).json({ error: 'stripe_account_session_failed', message: err.message });
  }
});

// Stripe webhook with signature verification
app.post('/stripe/webhook', express.raw({ type: 'application/json' }), async (req, res) => {
  if (!stripe) return res.status(500).send('stripe_not_configured');
  if (!STRIPE_WEBHOOK_SECRET) return res.status(500).send('webhook_secret_not_configured');
  const sig = req.headers['stripe-signature'];
  if (!sig) return res.status(400).send('missing_signature');
  try {
    const event = stripe.webhooks.constructEvent(req.body, sig as string, STRIPE_WEBHOOK_SECRET);
    if (event.type === 'account.updated' || event.type.startsWith('capability.')) {
      const acct = event.data.object as Stripe.Account;
      const qsnap = await SESSIONS.where('stripe.account_id', '==', acct.id).limit(1).get();
      if (!qsnap.empty) {
        const doc = qsnap.docs[0];
        const sessionId = doc.id;
        const status = acct.requirements?.disabled_reason ?? 'active';

        const businessAddress =
          acct.company?.address?.line1 ||
          acct.business_profile?.support_address?.line1 ||
          acct.business_profile?.url ||
          '';
        const country = acct.company?.address?.country || acct.business_profile?.support_address?.country;
        const phone = acct.business_profile?.support_phone || acct.company?.phone;
        const name = acct.business_profile?.name || acct.company?.name;

        let tz: any = {};
        try {
          tz = await geocodeTimezone(businessAddress, country || undefined);
        } catch (e) {
          console.error('geocode error', e);
        }

        const updates: any = {
          stripe: {
            account_id: acct.id,
            status,
            capabilities: acct.capabilities ?? {},
          },
          updated_at: Timestamp.now(),
        };

        if (name || phone || businessAddress || country || tz.timezone) {
          updates.business = {
            ...(doc.data().business ?? {}),
            ...(name ? { name } : {}),
            ...(phone ? { phone } : {}),
            ...(businessAddress ? { address: businessAddress } : {}),
            ...(country ? { country } : {}),
            ...(tz.timezone ? { timezone: tz.timezone } : {}),
            ...(tz.lat ? { lat: tz.lat, lng: tz.lng } : {}),
          };
        }

        await doc.ref.update(updates);
        await audit(sessionId, 'stripe_event', {
          type: event.type,
          status,
          enriched: Boolean(tz.timezone),
        });
      }
      try {
        await upsertDeliveryPartnerStripeFromAccount(firestore, acct);
      } catch (err) {
        console.error('delivery partner stripe webhook update failed', err);
      }
    }
    console.log('stripe event', event.type);
    res.json({ received: true, verified: true });
  } catch (err: any) {
    console.error('stripe webhook error', err.message);
    res.status(400).send(`Webhook Error: ${err.message}`);
  }
});

app.listen(PORT, () => {
  console.log(`Onboarding service listening on :${PORT}`);
});
