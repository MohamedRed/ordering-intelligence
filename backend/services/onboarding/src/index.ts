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
  createElevenLabsPhoneNumberImporter,
  createElevenLabsTemplateAgentResolver,
} from './elevenlabs_phone_numbers.js';
import {
  registerDeliveryPartnerStripeRoutes,
  upsertDeliveryPartnerStripeFromAccount,
} from './delivery_partner_stripe.js';
import { registerBusinessProfileRoutes } from './business_profile_routes.js';
import { registerDeliveryPartnerComplianceRoutes } from './delivery_partner_compliance.js';
import { registerMerchantStripeEmbedRoutes } from './merchant_stripe_embed.js';
import { registerFinalizeRoutes } from './finalize_routes.js';
import { maskPhone } from './phone_routes.js';
import { createPhoneNumberRouteStore } from './phone_number_route_store.js';
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
import type { OnboardingSession } from './onboarding_session_types.js';
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
const upsertPhoneNumberRoute = createPhoneNumberRouteStore(firestore.collection('phone_number_routes'));
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
const ensureElevenLabsPhoneNumberImported = createElevenLabsPhoneNumberImporter({
  apiKey: ELEVENLABS_API_KEY,
  apiBaseUrl: ELEVENLABS_API_BASE_URL,
  twilioAccountSid: TWILIO_ACCOUNT_SID,
  twilioAuthToken: TWILIO_AUTH_TOKEN,
  fetchImpl: fetch,
});

const storage = new Storage();
const bucket = storage.bucket(BUCKET);
const resolveElevenLabsTemplateAgentId = createElevenLabsTemplateAgentResolver({
  fastFoodAgentId: ELEVENLABS_TEMPLATE_FAST_FOOD_AGENT_ID,
  autoPartsAgentId: ELEVENLABS_TEMPLATE_AUTO_PARTS_AGENT_ID,
  gasStationAgentId: ELEVENLABS_TEMPLATE_GAS_STATION_AGENT_ID,
});

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
