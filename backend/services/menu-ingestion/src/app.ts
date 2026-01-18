import express from 'express';
import cors from 'cors';
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
      res.header('Access-Control-Allow-Origin', '*');
      res.header('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
      res.header('Access-Control-Allow-Headers', 'Authorization, Content-Type, Origin, Accept');
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
      const allowGoogle = String(process.env.ALLOW_GOOGLE_ID_TOKENS || '').toLowerCase() === 'true';
      if (!allowGoogle) {
        throw firebaseErr;
      }

      const host = req.get('host') || '';
      const forwardedProto = (req.get('x-forwarded-proto') || 'https').split(',')[0].trim();
      const audience = `${forwardedProto}://${host}`;

      const ticket = await googleOauth.verifyIdToken({ idToken: token, audience });
      const payload = ticket.getPayload();
      const email = String(payload?.email || '').trim().toLowerCase();

      const allowedEmails = String(process.env.GOOGLE_ID_TOKEN_ALLOWED_EMAILS || '')
        .split(',')
        .map((s) => s.trim().toLowerCase())
        .filter(Boolean);
      if (!email || (allowedEmails.length > 0 && !allowedEmails.includes(email))) {
        res.header('Access-Control-Allow-Origin', '*');
        res.header('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
        res.header('Access-Control-Allow-Headers', 'Authorization, Content-Type, Origin, Accept');
        return res.status(401).json({ error: 'invalid token' });
      }

      (req as any).user = payload;
      return next();
    }
  } catch (e) {
    console.error('auth failed', e);
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Authorization, Content-Type, Origin, Accept');
    return res.status(401).json({ error: 'invalid token' });
  }
}

// Express app
export const app = express();
app.use(express.json({ limit: '2mb' }));

// CORS: allow all origins for dev; ensure headers are set even on auth failures.
const corsOptions: cors.CorsOptions = {
  origin: (_origin, cb) => cb(null, true),
  credentials: true,
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Authorization', 'Content-Type', 'Origin', 'Accept'],
};
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Authorization, Content-Type, Origin, Accept');
  if (req.method === 'OPTIONS') {
    return res.sendStatus(200);
  }
  next();
});
app.use(cors(corsOptions));

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
    },
    null,
    2,
  ),
);

export default app;
