import express from 'express';
import { Storage } from '@google-cloud/storage';
import { PubSub } from '@google-cloud/pubsub';
import { Firestore } from '@google-cloud/firestore';
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { OAuth2Client } from 'google-auth-library';

import {
  bucketEnv,
  topicEnv,
  PROJECT,
  IMAGE_REGION,
  TEXT_REGION,
  VERTEX_PROJECT,
  COMPOSITE_MODEL,
  ANALYSIS_MODEL,
  RENDER_MODEL,
  GEN_TIMEOUT_MS,
  RENDER_TIMEOUT_MS,
  RENDER_RETRIES,
  RENDER_BASE_DELAY_MS,
  RENDER_MIN_INTERVAL_MS,
  AGENT_COMPOSITE_URL,
  AGENT_ANALYSIS_URL,
  AGENT_RETRIES,
  AGENT_BASE_DELAY_MS,
  AGENT_QUEUE_COLLECTION,
  AGENT_QUEUE_WAIT_MS,
  AGENT_CONFIG_DOC,
} from './config.js';
import { ingestRouter } from './routes/ingest.js';
import { agentRouter } from './routes/agent.js';
import { tasksRouter } from './routes/tasks.js';
import { cleanupRouter } from './routes/cleanup.js';
import { testRouter } from './routes/test.js';

export type AppContext = {
  firestore: Firestore;
  storage: Storage;
  pubsub: PubSub;
  bucket: string;
  topic: string;
  menuUpdatesTopic?: string;
  signedReadUrls: (files: string[]) => Promise<string[]>;
  requireAuth: express.RequestHandler;
};

if (!bucketEnv || !topicEnv) {
  throw new Error('MENU_BUCKET/STORAGE_BUCKET_MENUS and MENU_INGEST_TOPIC/PUBSUB_TOPIC_MENU_INGEST are required');
}
if (!VERTEX_PROJECT) {
  throw new Error('GOOGLE_CLOUD_PROJECT or VERTEX_PROJECT is required');
}

// Firebase Admin (for ID token verification)
initializeApp({ credential: applicationDefault(), projectId: process.env.GOOGLE_CLOUD_PROJECT });
const adminAuth = getAuth();
const googleOauth = new OAuth2Client();

const storage = new Storage();
const pubsub = new PubSub();
const firestore = new Firestore({ ignoreUndefinedProperties: true });

const BUCKET: string = bucketEnv;
const TOPIC: string = topicEnv;
const MENU_UPDATES_TOPIC = process.env.MENU_UPDATES_TOPIC ?? process.env.PUBSUB_TOPIC_MENU_UPDATES;

function csvValues(value?: string): string[] {
  return String(value || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

function isStrictEnvironment(): boolean {
  return ['prod', 'production', 'staging'].includes(
    String(process.env.ENVIRONMENT || process.env.NODE_ENV || '').trim().toLowerCase(),
  );
}

const configuredCorsOrigins = csvValues(process.env.MENU_INGESTION_CORS_ORIGINS ?? process.env.CORS_ORIGINS);
const corsOrigins = configuredCorsOrigins.length ? configuredCorsOrigins : (isStrictEnvironment() ? [] : ['*']);
const allowAnyCorsOrigin = corsOrigins.includes('*');
if (isStrictEnvironment()) {
  if (!corsOrigins.length) {
    throw new Error('MENU_INGESTION_CORS_ORIGINS or CORS_ORIGINS is required in staging/production');
  }
  if (allowAnyCorsOrigin) {
    throw new Error('Wildcard CORS origins are not allowed for menu-ingestion in staging/production');
  }
}

const googleIdTokenAudiences = csvValues(
  process.env.GOOGLE_ID_TOKEN_AUDIENCES ?? process.env.INTERNAL_AUTH_AUDIENCE,
);
const googleIdTokenAllowedEmails = csvValues(
  process.env.GOOGLE_ID_TOKEN_ALLOWED_EMAILS ?? process.env.INTERNAL_ALLOWED_EMAILS,
).map((email) => email.toLowerCase());
const allowGoogleIdTokens = String(process.env.ALLOW_GOOGLE_ID_TOKENS || '').toLowerCase() === 'true';
if (allowGoogleIdTokens && !googleIdTokenAudiences.length) {
  throw new Error('GOOGLE_ID_TOKEN_AUDIENCES or INTERNAL_AUTH_AUDIENCE is required when Google ID tokens are enabled');
}
if (allowGoogleIdTokens && !googleIdTokenAllowedEmails.length) {
  throw new Error('GOOGLE_ID_TOKEN_ALLOWED_EMAILS or INTERNAL_ALLOWED_EMAILS is required when Google ID tokens are enabled');
}

function applyCors(req: express.Request, res: express.Response): boolean {
  const origin = req.get('origin');
  if (!origin) return true;
  const allowed = allowAnyCorsOrigin || corsOrigins.includes(origin);
  if (!allowed) return false;
  res.header('Access-Control-Allow-Origin', allowAnyCorsOrigin ? origin : origin);
  res.header('Vary', 'Origin');
  res.header('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Authorization, Content-Type, Origin, Accept');
  res.header('Access-Control-Max-Age', '600');
  return true;
}

async function signedReadUrls(files: string[]): Promise<string[]> {
  const urls: string[] = [];
  for (const object of files) {
    try {
    const [url] = await storage.bucket(BUCKET).file(object).getSignedUrl({
      action: 'read',
      expires: Date.now() + 60 * 60 * 1000,
    });
    urls.push(url);
    } catch (e: any) {
      const msg = String(e?.message ?? e);
      if (msg.includes('Cannot sign data without') || msg.includes('client_email')) {
        throw new Error(
          `Signed URL generation failed (missing service account identity). ` +
            `You're likely running locally with user ADC. ` +
            `Fix: set GOOGLE_APPLICATION_CREDENTIALS to a service-account JSON key (with client_email/private_key) ` +
            `or run this on Cloud Run with a service account. Original error: ${msg}`,
        );
      }
      throw e;
    }
  }
  return urls;
}

// Simple auth middleware for admin endpoints
async function requireAuth(req: express.Request, res: express.Response, next: express.NextFunction) {
  try {
    const header = req.header('Authorization');
    if (!header || !header.toLowerCase().startsWith('bearer ')) {
      return res.status(401).json({ error: 'missing bearer token' });
    }
    const token = header.substring(7);
    // 1) Primary: Firebase ID token (admin UI).
    try {
      const decoded = await adminAuth.verifyIdToken(token);
      (req as any).user = decoded;
      return next();
    } catch (firebaseErr) {
      // 2) Optional: Google IAM OIDC identity token (for ops scripts).
      if (!allowGoogleIdTokens) {
        throw firebaseErr;
      }

      const ticket = await googleOauth.verifyIdToken({ idToken: token, audience: googleIdTokenAudiences });
      const payload = ticket.getPayload();
      const email = String(payload?.email || '').trim().toLowerCase();

      if (!email || (googleIdTokenAllowedEmails.length > 0 && !googleIdTokenAllowedEmails.includes(email))) {
        return res.status(401).json({ error: 'invalid token' });
      }

      (req as any).user = payload;
      return next();
    }
  } catch (e) {
    console.error('auth failed', e);
    return res.status(401).json({ error: 'invalid token' });
  }
}

// Express app
export const app = express();
app.use(express.json({ limit: '2mb' }));

app.use((req, res, next) => {
  const corsAllowed = applyCors(req, res);
  if (req.method === 'OPTIONS') {
    return res.sendStatus(corsAllowed ? 204 : 403);
  }
  if (!corsAllowed) {
    return res.status(403).json({ error: 'origin_not_allowed' });
  }
  next();
});

// Health
app.get('/health', (_req, res) => res.json({ ok: true }));

const ctx: AppContext = {
  firestore,
  storage,
  pubsub,
  bucket: BUCKET,
  topic: TOPIC,
  menuUpdatesTopic: MENU_UPDATES_TOPIC || undefined,
  signedReadUrls,
  requireAuth,
};

// Routes
app.use(ingestRouter(ctx));
app.use(agentRouter(ctx));
app.use(tasksRouter(ctx));
app.use(cleanupRouter(ctx));
app.use(testRouter(ctx));

console.log(
  'menu-ingestion config',
  JSON.stringify(
    {
      project: PROJECT,
      bucket: BUCKET,
      topic: TOPIC,
      imageRegion: IMAGE_REGION,
      textRegion: TEXT_REGION,
      compositeModel: COMPOSITE_MODEL,
      analysisModel: ANALYSIS_MODEL,
      renderModel: RENDER_MODEL,
      genTimeoutMs: GEN_TIMEOUT_MS,
      renderTimeoutMs: RENDER_TIMEOUT_MS,
      renderRetries: RENDER_RETRIES,
      renderBaseDelayMs: RENDER_BASE_DELAY_MS,
      renderMinIntervalMs: RENDER_MIN_INTERVAL_MS,
      agentCompositeUrl: AGENT_COMPOSITE_URL,
      agentAnalysisUrl: AGENT_ANALYSIS_URL,
      agentRetries: AGENT_RETRIES,
      agentBaseDelayMs: AGENT_BASE_DELAY_MS,
      agentQueue: AGENT_QUEUE_COLLECTION,
      agentWaitMs: AGENT_QUEUE_WAIT_MS,
      agentConfigDoc: AGENT_CONFIG_DOC,
      menuUpdatesTopic: MENU_UPDATES_TOPIC,
      corsOrigins: allowAnyCorsOrigin ? ['*'] : corsOrigins,
      googleIdTokenAudiences,
      googleIdTokenAllowedEmails,
    },
    null,
    2,
  ),
);

export default app;
