import express from 'express';
import { Storage } from '@google-cloud/storage';
import { PubSub } from '@google-cloud/pubsub';
import { Firestore } from '@google-cloud/firestore';
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { GoogleAuth } from 'google-auth-library';
import { v4 as uuidv4 } from 'uuid';
import cors from 'cors';
import { VertexAI } from '@google-cloud/vertexai';
import { client as gradioClient } from '@gradio/client';

import type {
  DraftMenu,
  IngestJob,
  IngestStartRequest,
  MenuItem,
} from './types';

const app = express();
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

// Firebase Admin (for ID token verification)
initializeApp({ credential: applicationDefault(), projectId: process.env.GOOGLE_CLOUD_PROJECT });
const adminAuth = getAuth();

const bucketEnv = process.env.MENU_BUCKET ?? process.env.STORAGE_BUCKET_MENUS;
const topicEnv = process.env.MENU_INGEST_TOPIC ?? process.env.PUBSUB_TOPIC_MENU_INGEST;
const PROJECT = process.env.GOOGLE_CLOUD_PROJECT ?? process.env.GCP_PROJECT;
// Gemini image preview is served from the global endpoint.
const IMAGE_REGION = process.env.IMAGE_REGION ?? 'global';
// Text models (analysis) run from a standard Vertex region.
const TEXT_REGION = process.env.TEXT_REGION ?? process.env.VERTEX_LOCATION ?? 'global';
const VERTEX_PROJECT = process.env.VERTEX_PROJECT ?? PROJECT;
// Default to Vertex-available image model (no API key).
// Default to Gemini 3 Pro Image Preview (image+text capable) for rendering.
const COMPOSITE_MODEL = process.env.COMPOSITE_MODEL ?? 'gemini-3-pro-image-preview';
// Model used to analyze composites (count/detect cards).
const ANALYSIS_MODEL = process.env.ANALYSIS_MODEL ?? 'gemini-3-pro-preview';
const RENDER_MODEL = process.env.RENDER_MODEL ?? COMPOSITE_MODEL;
const GEN_TIMEOUT_MS = Number(process.env.GEN_TIMEOUT_MS ?? 120_000);
const RENDER_TIMEOUT_MS = Number(process.env.RENDER_TIMEOUT_MS ?? 120_000);
// Keep exactly one attempt on Vertex; fallback to agent if that single call fails.
const RENDER_RETRIES = 1;
const RENDER_BASE_DELAY_MS = Number(process.env.RENDER_BASE_DELAY_MS ?? 10_000); // start at 10s
const RENDER_MIN_INTERVAL_MS = Number(process.env.RENDER_MIN_INTERVAL_MS ?? 10_000); // 10s spacing between image calls
const AGENT_COMPOSITE_URL = process.env.AGENT_COMPOSITE_URL;
const AGENT_ANALYSIS_URL = process.env.AGENT_ANALYSIS_URL;
const AGENT_RETRIES = Number(process.env.AGENT_RETRIES ?? 3);
const AGENT_BASE_DELAY_MS = Number(process.env.AGENT_BASE_DELAY_MS ?? 3000);
const AGENT_QUEUE_COLLECTION = process.env.AGENT_QUEUE_COLLECTION ?? 'agent_jobs';
const AGENT_QUEUE_WAIT_MS = Number(process.env.AGENT_QUEUE_WAIT_MS ?? 90_000); // wait for laptop worker before failing
const AGENT_CONFIG_DOC = process.env.AGENT_CONFIG_DOC ?? 'agent_worker/config';

// Serialize Gemini image calls to avoid 429 bursts.
let renderLock: Promise<void> = Promise.resolve();
let lastRenderStart = 0;
async function withRenderSlot<T>(fn: () => Promise<T>): Promise<T> {
  const prev = renderLock;
  let release: () => void = () => {};
  renderLock = new Promise<void>((resolve) => {
    release = resolve;
  });
  await prev;
  // Throttle: enforce a minimum interval between render requests.
  const now = Date.now();
  const since = now - lastRenderStart;
  if (since < RENDER_MIN_INTERVAL_MS) {
    await delay(RENDER_MIN_INTERVAL_MS - since);
  }
  lastRenderStart = Date.now();
  try {
    return await fn();
  } finally {
    release();
  }
}

if (!bucketEnv || !topicEnv) {
  throw new Error('MENU_BUCKET/STORAGE_BUCKET_MENUS and MENU_INGEST_TOPIC/PUBSUB_TOPIC_MENU_INGEST are required');
}
if (!VERTEX_PROJECT) {
  throw new Error('GOOGLE_CLOUD_PROJECT or VERTEX_PROJECT is required');
}

const BUCKET: string = bucketEnv;
const TOPIC: string = topicEnv;

const storage = new Storage();
const pubsub = new PubSub();
const firestore = new Firestore();
const vertexText = new VertexAI({ project: VERTEX_PROJECT, location: TEXT_REGION });
const textModel = (modelId: string) => vertexText.getGenerativeModel({ model: modelId });
const auth = new GoogleAuth({ scopes: 'https://www.googleapis.com/auth/cloud-platform' });
// Use Vertex AI auth (service account) for image generation (Gemini 3 on global endpoint).
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
    },
    null,
    2
  )
);

if (!bucketEnv || !topicEnv) {
  throw new Error('MENU_BUCKET/STORAGE_BUCKET_MENUS and MENU_INGEST_TOPIC/PUBSUB_TOPIC_MENU_INGEST are required');
}
if (!VERTEX_PROJECT) {
  throw new Error('GOOGLE_CLOUD_PROJECT or VERTEX_PROJECT is required');
}

app.get('/health', (_req, res) => res.json({ ok: true }));

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
    const decoded = await adminAuth.verifyIdToken(token);
    (req as any).user = decoded;
    return next();
  } catch (e) {
    console.error('auth failed', e);
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Authorization, Content-Type, Origin, Accept');
    return res.status(401).json({ error: 'invalid token' });
  }
}

// List recent jobs
app.get('/ingest', requireAuth, async (req, res) => {
  const limit = Number(req.query.limit ?? 20);
  const snap = await firestore
    .collection('menus_ingest')
    .orderBy('updatedAt', 'desc')
    .limit(Math.max(1, Math.min(limit, 50)))
    .get();
  const jobs = snap.docs.map((d) => d.data());
  res.json({ jobs });
});

// Agent queue introspection (admin)
app.get('/agent-jobs', requireAuth, async (_req, res) => {
  const snap = await firestore
    .collection(AGENT_QUEUE_COLLECTION)
    .orderBy('createdAt', 'desc')
    .limit(50)
    .get();
  const jobs = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  res.json({ jobs });
});

// Agent worker config (enable/disable polling)
app.get('/agent-worker/config', requireAuth, async (_req, res) => {
  const doc = await firestore.doc(AGENT_CONFIG_DOC).get();
  const cfg = doc.exists ? doc.data() : { enabled: false };
  res.json(cfg);
});

app.post('/agent-worker/config', requireAuth, async (req, res) => {
  const enabled = Boolean(req.body?.enabled);
  await firestore.doc(AGENT_CONFIG_DOC).set({ enabled, updatedAt: Date.now() }, { merge: true });
  res.json({ enabled });
});

// Helper: generate signed READ urls for uploaded menu files
async function signedReadUrls(files: string[]): Promise<string[]> {
  const urls: string[] = [];
  for (const object of files) {
    const [url] = await storage.bucket(BUCKET).file(object).getSignedUrl({
      action: 'read',
      expires: Date.now() + 60 * 60 * 1000, // 1 hour
    });
    urls.push(url);
  }
  return urls;
}

// 1) Start: generate signed URLs for uploads
app.post('/ingest/start', async (req, res) => {
  const body = req.body as IngestStartRequest;
  if (!body.restaurantId || !body.pageCount || body.pageCount < 1) {
    return res.status(400).json({ error: 'restaurantId and pageCount are required' });
  }

  const jobId = uuidv4();
  const now = Date.now();
  const files: string[] = [];
  const signedUrls: string[] = [];

  for (let i = 0; i < body.pageCount; i++) {
    const object = `menu-raw/${body.restaurantId}/${jobId}/page-${i + 1}.jpg`;
    const [url] = await storage.bucket(BUCKET).file(object).getSignedUrl({
      action: 'write',
      expires: Date.now() + 15 * 60 * 1000,
      contentType: 'image/jpeg',
    });
    files.push(object);
    signedUrls.push(url);
  }

  const job: IngestJob = {
    jobId,
    restaurantId: body.restaurantId,
    status: 'uploading',
    files,
    createdAt: now,
    updatedAt: now,
  };

  await firestore.collection('menus_ingest').doc(jobId).set(job);

  res.json({ jobId, uploadUrls: signedUrls });
});

// 2) Submit for processing (after uploads)
app.post('/ingest/submit', async (req, res) => {
  const { jobId } = req.body as { jobId?: string };
  if (!jobId) return res.status(400).json({ error: 'jobId required' });

  const jobRef = firestore.collection('menus_ingest').doc(jobId);
  const snap = await jobRef.get();
  if (!snap.exists) return res.status(404).json({ error: 'job not found' });

  await jobRef.update({ status: 'queued', updatedAt: Date.now() });
  await pubsub.topic(TOPIC).publishMessage({ json: { jobId } });

  res.json({ jobId, status: 'queued' });
});

// 3) Poll job
app.get('/ingest/:jobId', async (req, res) => {
  const snap = await firestore.collection('menus_ingest').doc(req.params.jobId).get();
  if (!snap.exists) return res.status(404).json({ error: 'not found' });
  res.json(snap.data());
});

// 3b) Fetch draft (including items and viewable image URLs)
app.get('/ingest/:jobId/draft', requireAuth, async (req, res) => {
  const { jobId } = req.params;
  const draftSnap = await firestore.collection('menus_drafts').doc(jobId).get();
  if (!draftSnap.exists) return res.status(404).json({ error: 'draft not found' });

  const jobSnap = await firestore.collection('menus_ingest').doc(jobId).get();
  const files = jobSnap.exists ? (jobSnap.data() as IngestJob).files : [];
  const fileUrls = files.length ? await signedReadUrls(files) : [];

  res.json({
    jobId,
    draft: draftSnap.data(),
    files,
    fileUrls,
  });
});

// 4) Approve draft
app.post('/ingest/:jobId/approve', requireAuth, async (req, res) => {
  const { jobId } = req.params;
  const draftSnap = await firestore.collection('menus_drafts').doc(jobId).get();
  if (!draftSnap.exists) return res.status(404).json({ error: 'draft not found' });
  const draft = draftSnap.data() as DraftMenu;

  const batch = firestore.batch();
  const menuColl = firestore
    .collection('restaurants')
    .doc(draft.restaurantId)
    .collection('menus');

  draft.items.forEach((item) => {
    const id = item.id || uuidv4();
    batch.set(menuColl.doc(id), item, { merge: true });
  });

  batch.update(firestore.collection('menus_ingest').doc(jobId), {
    status: 'ready',
    updatedAt: Date.now(),
  });

  await batch.commit();

  res.json({ status: 'published', items: draft.items.length });
});

// 5) Pub/Sub push endpoint to process a job
app.post('/tasks/process', async (req, res) => {
  const message = parsePubSubBody(req.body);
  if (!message?.jobId) {
    return res.status(400).json({ error: 'missing jobId' });
  }

  const jobId = message.jobId as string;
  const jobRef = firestore.collection('menus_ingest').doc(jobId);
  const jobSnap = await jobRef.get();
  if (!jobSnap.exists) {
    return res.status(404).json({ error: 'job not found' });
  }
  const job = jobSnap.data() as IngestJob;

  await jobRef.update({ status: 'processing', updatedAt: Date.now() });

  try {
    const menuFromOriginal = await analyzeMenuFromOriginal(job.files);

    const composites = await generateComposites(job.files, jobId);
    const compositeUrls = await signedReadUrls(composites.generatedFiles);
    const extracted = await extractItemsFromComposites(composites.generatedFiles, jobId);
    let geminiItems = extracted.images;

    // Fallback: if the model couldn't isolate items, at least pass the composite through
    if (!geminiItems.length && composites.generatedFiles.length) {
      const first = composites.generatedFiles[0];
      const [url] = await storage
        .bucket(BUCKET)
        .file(first)
        .getSignedUrl({ action: 'read', expires: Date.now() + 7 * 24 * 60 * 60 * 1000 });
      geminiItems = [{ name: 'menu_page_1', url, storagePath: first }];
    }

    const items = await assignThumbsToMenu(menuFromOriginal, geminiItems);

    if (!items.length) {
      throw new Error('no items extracted from thumbnails');
    }

    const draft: DraftMenu = {
      jobId,
      restaurantId: job.restaurantId,
      items,
      ocrLines: [],
      compositeUrls,
      detectedItemCount: menuFromOriginal.length || extracted.count,
      createdAt: job.createdAt,
      updatedAt: Date.now(),
    };

    await firestore.collection('menus_drafts').doc(jobId).set(draft);
    await jobRef.update({ status: 'ready', draftRef: `menus_drafts/${jobId}`, updatedAt: Date.now() });
  } catch (error: any) {
    console.error('ingest failed', { jobId, error });
    await jobRef.update({ status: 'error', issues: [String(error?.message ?? error)], updatedAt: Date.now() });
  }

  res.json({ ok: true });
});

function parsePubSubBody(body: any): any {
  if (body?.message?.data) {
    const raw = Buffer.from(body.message.data, 'base64').toString('utf8');
    try {
      return JSON.parse(raw);
    } catch {
      return undefined;
    }
  }
  return body;
}

type GeneratedComposite = { generatedFiles: string[] };
type ExtractedItems = { images: GeminiItemImage[]; count: number };

type GeminiItemImage = { name: string; url: string; storagePath: string };

function logVertexError(stage: string, err: any, extra?: Record<string, unknown>) {
  const dataSnippet =
    typeof err?.response?.data === 'string' ? err.response.data.slice(0, 400) : err?.response?.data;
  console.error(`${stage} vertex error`, {
    stage,
    status: err?.response?.status,
    statusText: err?.response?.statusText,
    headers: err?.response?.headers,
    dataSnippet,
    message: err?.message ?? String(err),
    ...extra,
  });
}

async function renderCompositeViaAgent(object: string, prompt: string): Promise<Buffer | undefined> {
  if (!AGENT_COMPOSITE_URL) return undefined;
  try {
    const [signedUrl] = await storage.bucket(BUCKET).file(object).getSignedUrl({
      action: 'read',
      expires: Date.now() + 15 * 60 * 1000,
    });

    const res = await fetchGradio(AGENT_COMPOSITE_URL, prompt, signedUrl);
    if (!res) return undefined;

    if (res.inlineData) return Buffer.from(res.inlineData, 'base64');
    if (res.url) {
      const fetchRes = await fetch(res.url);
      if (!fetchRes.ok) return undefined;
      const arrayBuf = await fetchRes.arrayBuffer();
      return Buffer.from(arrayBuf);
    }
    return undefined;
  } catch (err) {
    console.error('renderCompositeViaAgent error', err);
    return undefined;
  }
}

// Shared generation config for image-producing calls (Gemini 3 Pro image preview).
// Mirrors the sample known to work with the pipeline tests.
const IMAGE_GEN_CONFIG: any = {
  maxOutputTokens: 32768,
  temperature: 1,
  topP: 0.95,
  responseModalities: ['TEXT', 'IMAGE'],
  imageConfig: {
    aspectRatio: '1:1',
    // Vertex accepts discrete presets; '1K' matches the working single_composite.js call. Smaller custom sizes (e.g., '768') trigger INVALID_ARGUMENT.
    imageSize: '1K',
  },
};

const IMAGE_SAFETY: any[] = [
  { category: 'HARM_CATEGORY_HATE_SPEECH', threshold: 'OFF' },
  { category: 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold: 'OFF' },
  { category: 'HARM_CATEGORY_SEXUALLY_EXPLICIT', threshold: 'OFF' },
  { category: 'HARM_CATEGORY_HARASSMENT', threshold: 'OFF' },
];

async function analyzeMenuFromOriginal(files: string[]): Promise<MenuItem[]> {
  const results: MenuItem[] = [];
  for (const object of files) {
    const fileUri = `gs://${BUCKET}/${object}`;
    let parsed = await analyzeOriginalViaVertex(fileUri, 'image/jpeg');
    if ((!parsed || !parsed.length) && AGENT_ANALYSIS_URL) {
      parsed = await analyzeOriginalViaAgent(fileUri, 'image/jpeg');
    }
    if (Array.isArray(parsed)) {
      for (const it of parsed) {
        if (it?.name) {
          results.push({
            id: it.id ?? slugifyName(it.name),
            name: it.name,
            category: it.category ?? undefined,
            price: typeof it.price === 'number' ? it.price : undefined,
            currency: it.currency ?? undefined,
            available: it.available ?? true,
            imageUrl: undefined,
            photoUrl: undefined,
          });
        }
      }
    }
  }
  return results;
}

async function analyzeOriginalViaVertex(fileUri: string, mimeType: string): Promise<any[]> {
  const prompt =
    'Read this menu page image and return JSON array of items: [{id, name, category, price, currency, available}]. ' +
    'Use only visible text; map €, £, $ to EUR, GBP, USD. Do not invent items.';
  const body = {
    contents: [
      {
        role: 'user',
        parts: [
          { text: prompt },
          { fileData: { fileUri, mimeType } },
        ],
      },
    ],
    generationConfig: {
      responseMimeType: 'application/json',
      temperature: 0.2,
    },
  };

  const url = `https://aiplatform.googleapis.com/v1/projects/${VERTEX_PROJECT}/locations/${TEXT_REGION}/publishers/google/models/${ANALYSIS_MODEL}:generateContent`;

  try {
    const token = await auth.getAccessToken();
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), GEN_TIMEOUT_MS);
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    clearTimeout(timeout);
    const contentType = res.headers.get('content-type') || '';
    const resText = await res.text();
    if (!res.ok || !contentType.includes('application/json')) {
      console.error('analyze-original fetch failed', {
        status: res.status,
        statusText: res.statusText,
        bodySnippet: resText.slice(0, 400),
        contentType,
      });
      return [];
    }
    let parsedResp: any;
    try {
      parsedResp = JSON.parse(resText);
    } catch (e) {
      console.error('analyze-original response parse error', { message: (e as Error).message, resText: resText.slice(0, 200) });
      return [];
    }
    const text =
      parsedResp?.candidates
        ?.flatMap((c: any) => c?.content?.parts ?? [])
        ?.find((p: any) => p?.text)?.text;
    if (!text) return [];
    try {
      const parsed = JSON.parse(text);
      return Array.isArray(parsed) ? parsed : [];
    } catch (e) {
      console.error('analyze original parse error', e);
      return [];
    }
  } catch (err) {
    logVertexError('analyze-original', err, { fileUri });
    // enqueue for external worker if available
    const docId = `analysis-${slugifyName(fileUri)}-${Buffer.from(fileUri).toString('base64').slice(0, 8)}`;
    const queued = await enqueueAgentJob('analysis', prompt, fileUri, mimeType, ANALYSIS_MODEL, docId);
    if (queued) {
      const res = await waitForAgentJob(queued, 'analysis');
      const text = res?.outputText;
      if (text) {
        try {
          const parsed = JSON.parse(text);
          return Array.isArray(parsed) ? parsed : [];
        } catch {
          return [];
        }
      }
    }
    return [];
  }
}

async function analyzeOriginalViaAgent(fileUri: string, _mimeType: string): Promise<any[]> {
  if (!AGENT_ANALYSIS_URL) return [];
  try {
    // For agent, provide a signed URL
    const [signedUrl] = await storage.bucket(BUCKET).file(fileUri.replace(`gs://${BUCKET}/`, '')).getSignedUrl({
      action: 'read',
      expires: Date.now() + 15 * 60 * 1000,
    });
    const res = await fetchGradio(AGENT_ANALYSIS_URL, 'Extract menu items as JSON array [{id,name,category,price,currency,available}]', signedUrl);
    if (!res) return [];
    if (res.text) {
      try {
        const arr = JSON.parse(res.text);
        return Array.isArray(arr) ? arr : [];
      } catch {
        return [];
      }
    }
    return [];
  } catch (err) {
    console.error('analyzeOriginalViaAgent error', err);
    return [];
  }
}

async function generateComposites(files: string[], jobId: string): Promise<GeneratedComposite> {
  const generatedFiles: string[] = [];
  let page = 0;
  for (const object of files) {
    page += 1;
    try {
      const prompt =
        'So this is a page, a part of a menu of fast food containing different items, bundles, etc, probably organized by categories, with maybe a text next to each item with a price probably, or maybe a description. ' +
        'Can you separate all of these purchasable elements of the menu in a composite in order to use them as thumbnails into a menu visualizer for the personnel of the fast food and the clients? ' +
        'Keep each dish together with its text and price. Output one image with all separated dishes neatly laid out on white.';

      let b64: string | undefined;

      // Try Vertex first
      b64 = await renderImage({
        prompt,
        mimeType: 'image/jpeg',
        fileUri: `gs://${BUCKET}/${object}`,
        modelId: COMPOSITE_MODEL,
        label: `composite-${jobId}-p${page}`,
      });

      // If Vertex failed, try agent as fallback
      if (!b64 && AGENT_COMPOSITE_URL) {
        try {
          const buf = await renderCompositeViaAgent(object, prompt);
          if (buf) {
            b64 = buf.toString('base64');
          }
        } catch (agentErr) {
          console.error('agent composite error', agentErr);
        }
      }

      if (!b64) {
        throw new Error(`composite generation returned empty image for page ${page}`);
      }
      const compositeBuffer = Buffer.from(b64, 'base64');
      const dest = `menu-generated/${jobId}/page-${page}.png`;
      await storage.bucket(BUCKET).file(dest).save(compositeBuffer, {
        contentType: 'image/png',
        resumable: false,
        metadata: { cacheControl: 'public,max-age=86400' },
      });
      generatedFiles.push(dest);
    } catch (err: any) {
      logVertexError('generate composite', err, { page, model: COMPOSITE_MODEL });
      throw err;
    }
  }

  if (generatedFiles.length === 0) {
    throw new Error('no composites generated');
  }
  return { generatedFiles };
}

async function extractItemsFromComposites(files: string[], jobId: string): Promise<ExtractedItems> {
  const results: GeminiItemImage[] = [];
  let detectedCount = 0;
  let page = 0;
  for (const object of files) {
    page += 1;
    try {
      // Step 1: ask for count and names
      const countPrompt =
        'How many individual cards/items are in this composite image? Return strict JSON like { "count": 12 } with no other text.';
      const countResp = await geminiJson(countPrompt, `gs://${BUCKET}/${object}`, 'image/png');
      const count = Number(countResp?.count ?? 0);
      if (!count || Number.isNaN(count)) {
        throw new Error('gemini item count missing');
      }
      detectedCount = Math.max(detectedCount, count);

      for (let idx = 1; idx <= count; idx++) {
        const imgPrompt = `Give me element #${idx} from this composite (the ${ordinal(
          idx
        )} purchasable menu item). Render it alone on a clean white background with its text and price visible. Return only the image (png).`;
        const imageBuffer = await geminiImage(imgPrompt, `gs://${BUCKET}/${object}`, 'image/png');
        if (!imageBuffer) {
          throw new Error(`rendered item #${idx} missing`);
        }
        const dest = `menu-items/${jobId}/page-${page}-item-${idx}.png`;
        await storage.bucket(BUCKET).file(dest).save(imageBuffer, {
          contentType: 'image/png',
          resumable: false,
          metadata: { cacheControl: 'public,max-age=86400' },
        });
        const [url] = await storage
          .bucket(BUCKET)
          .file(dest)
          .getSignedUrl({ action: 'read', expires: Date.now() + 7 * 24 * 60 * 60 * 1000 });
        results.push({ name: `item_${page}_${idx}`, url, storagePath: dest });
      }
    } catch (err) {
      console.error('extract items from composite error', err);
    }
  }
  return { images: results, count: detectedCount };
}

async function withTimeout<T>(promise: Promise<T>, ms: number, label: string): Promise<T> {
  let timeout: NodeJS.Timeout;
  const wrapped = new Promise<never>((_, reject) => {
    timeout = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
  });
  try {
    return await Promise.race([promise, wrapped]);
  } finally {
    clearTimeout(timeout!);
  }
}

async function assignThumbsToMenu(menu: MenuItem[], thumbs: GeminiItemImage[]): Promise<MenuItem[]> {
  const menuJson = menu.length ? JSON.stringify(menu) : undefined;
  const thumbItems: MenuItem[] = [];

  for (const thumb of thumbs) {
    const parsed = await describeThumbWithContext(menuJson, thumb);
    thumbItems.push(parsedToItem(parsed, thumb));
  }

  if (!menu.length) return thumbItems;
  return mergeMenuWithThumbs(menu, thumbItems);
}

async function describeThumbWithContext(menuJson: string | undefined, thumb: GeminiItemImage): Promise<any> {
  const prompt =
    'You will be given a menu (as JSON) and a thumbnail image of a menu item. ' +
    'Return JSON for the best matching item with fields {id, name, category, price, currency, available}. ' +
    'Prefer ids/names from the provided menu if they match the thumbnail. ' +
    'If no menu is provided, infer from the image only. ' +
    (menuJson ? `Menu JSON: ${menuJson}` : 'No menu JSON provided.');

  let parsed: any = await describeThumbViaVertex(prompt, thumb);
  if ((!parsed || Object.keys(parsed).length === 0) && AGENT_ANALYSIS_URL) {
    parsed = await describeThumbViaAgent(prompt, thumb);
  }
  return parsed;
}

function parsedToItem(parsed: any, thumb: GeminiItemImage): MenuItem {
  const name = parsed?.name ?? thumb.name ?? 'item';
  const id = parsed?.id ?? slugifyName(name);
  return {
    id,
    name,
    category: parsed?.category ?? undefined,
    price: typeof parsed?.price === 'number' ? parsed.price : undefined,
    currency: parsed?.currency ?? undefined,
    available: parsed?.available ?? true,
    imageUrl: thumb.url,
    photoUrl: thumb.url,
  };
}

async function geminiJson(prompt: string, fileUri: string, mimeType: string): Promise<any> {
  const body = {
    contents: [
      {
        role: 'user',
        parts: [
          { text: prompt },
          { fileData: { fileUri, mimeType } },
        ],
      },
    ],
    generationConfig: {
      responseMimeType: 'application/json',
      temperature: 0.1,
    },
  };

  const url = `https://aiplatform.googleapis.com/v1/projects/${VERTEX_PROJECT}/locations/${TEXT_REGION}/publishers/google/models/${ANALYSIS_MODEL}:generateContent`;

  let resText = '';
  try {
    const token = await auth.getAccessToken();
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), GEN_TIMEOUT_MS);
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    clearTimeout(timeout);
    resText = await res.text();
    const contentType = res.headers.get('content-type') || '';
    if (!res.ok || !contentType.includes('application/json')) {
      console.error('analysis-json fetch failed', {
        status: res.status,
        statusText: res.statusText,
        bodySnippet: resText.slice(0, 400),
        contentType,
      });
      throw new Error(`analysis-json failed status ${res.status}`);
    }
  } catch (err) {
    logVertexError('analysis-json', err, { model: ANALYSIS_MODEL });
    throw err;
  }

  let parsedResp: any;
  try {
    parsedResp = JSON.parse(resText);
  } catch (e) {
    console.error('analysis-json response parse error', { message: (e as Error).message, resText: resText.slice(0, 200) });
    return undefined;
  }

  const text =
    parsedResp?.candidates
      ?.flatMap((c: any) => c?.content?.parts ?? [])
      ?.find((p: any) => p?.text)?.text;
  if (!text) {
    console.warn('gemini json missing text', { model: ANALYSIS_MODEL, raw: parsedResp });
    return undefined;
  }
  try {
    return JSON.parse(text);
  } catch (e) {
    console.error('gemini json parse error', e);
    return undefined;
  }
}

async function geminiImage(prompt: string, fileUri: string, mimeType: string): Promise<Buffer | undefined> {
  const b64 = await renderImage({
    prompt,
    mimeType,
    fileUri,
    modelId: RENDER_MODEL,
    label: 'render',
  });
  if (!b64) return undefined;
  return Buffer.from(b64, 'base64');
}

function ordinal(n: number): string {
  const s = ['th', 'st', 'nd', 'rd'];
  const v = n % 100;
  return n + (s[(v - 20) % 10] || s[v] || s[0]);
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function slugifyName(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '') || 'item';
}

function parseGsUri(uri: string): { bucket: string; object: string } {
  const trimmed = uri.replace('gs://', '');
  const parts = trimmed.split('/');
  const bucket = parts.shift() ?? '';
  const object = parts.join('/');
  return { bucket, object };
}

function mergeMenuWithThumbs(menu: MenuItem[], thumbs: MenuItem[]): MenuItem[] {
  if (!menu.length) return thumbs;
  const bySlug = new Map<string, MenuItem>();
  for (const m of menu) {
    bySlug.set(slugifyName(m.name), { ...m });
  }

  const used = new Set<string>();
  const merged: MenuItem[] = [];

  for (const t of thumbs) {
    const slug = slugifyName(t.name);
    const base = bySlug.get(slug);
    if (base) {
      merged.push({
        ...base,
        price: base.price ?? t.price,
        currency: base.currency ?? t.currency,
        category: base.category ?? t.category,
        imageUrl: t.imageUrl ?? base.imageUrl,
        photoUrl: t.photoUrl ?? base.photoUrl,
      });
      used.add(slug);
    } else {
      merged.push(t);
    }
  }

  for (const [slug, m] of bySlug.entries()) {
    if (!used.has(slug)) merged.push(m);
  }

  return merged;
}

async function describeThumbViaVertex(prompt: string, thumb: GeminiItemImage): Promise<any> {
  try {
    const data: any = await withTimeout(
      textModel(ANALYSIS_MODEL).generateContent({
        contents: [
          {
            role: 'user',
            parts: [
              { text: prompt },
              {
                fileData: {
                  fileUri: `gs://${BUCKET}/${thumb.storagePath}`,
                  mimeType: 'image/png',
                },
              },
            ],
          },
        ],
        generationConfig: {
          responseMimeType: 'application/json',
          temperature: 0.2,
        },
      }),
      GEN_TIMEOUT_MS,
      'describe-thumb'
    );

    const text =
      data?.response?.candidates
        ?.flatMap((c: any) => c?.content?.parts ?? [])
        ?.find((p: any) => p?.text)?.text;
    if (!text) return {};
    try {
      return JSON.parse(text);
    } catch (e) {
      console.error('thumb json parse error', e);
      return {};
    }
  } catch (err) {
    logVertexError('describe-thumb', err, { model: ANALYSIS_MODEL });
    return {};
  }
}

async function describeThumbViaAgent(prompt: string, thumb: GeminiItemImage): Promise<any> {
  if (!AGENT_ANALYSIS_URL) return {};
  try {
    const [signedUrl] = await storage.bucket(BUCKET).file(thumb.storagePath).getSignedUrl({
      action: 'read',
      expires: Date.now() + 15 * 60 * 1000,
    });

    const res = await fetchGradio(AGENT_ANALYSIS_URL, prompt, signedUrl);
    if (!res) return {};
    if (res.text) {
      try {
        return JSON.parse(res.text);
      } catch {
        return {};
      }
    }
    return {};
  } catch (err) {
    console.error('describeThumbViaAgent error', err);
    return {};
  }
}

type GradioResult = { text?: string; inlineData?: string; url?: string };

async function fetchGradio(baseUrl: string, text: string, fileUrl: string): Promise<GradioResult | undefined> {
  const form = new FormData();
  form.append('data', text);
  form.append('file', fileUrl);

  const paths = [`${baseUrl}/chat`, `${baseUrl}/chat/`];
  let last: Response | undefined;
  for (let attempt = 1; attempt <= AGENT_RETRIES; attempt++) {
    for (const url of paths) {
      const res = await fetch(url, { method: 'POST', body: form });
      last = res;
      if (res.status === 404) continue;
      if (res.status === 429 || res.status >= 500) {
        if (attempt < AGENT_RETRIES) {
          const backoff = AGENT_BASE_DELAY_MS * Math.pow(2, attempt - 1);
          const jitter = Math.floor(Math.random() * 500);
          await delay(backoff + jitter);
          break;
        }
      }
      try {
        const parsed: any = await res.json();
        // Gradio can return list or object; try common shapes
        const data = parsed?.data ?? parsed;
        if (Array.isArray(data) && data.length) {
          const first = data[0];
          if (typeof first === 'string') return { text: first };
          if (first?.url) return { url: first.url };
          if (first?.path) return { url: first.path };
          if (first?.data) return { inlineData: first.data };
        }
      } catch {
        // fall through
      }
      return undefined;
    }
  }
  return undefined;
}

const port = process.env.PORT ?? 8080;
app.listen(port, () => {
  console.log(`menu-ingestion listening on :${port}`);
});

type RenderImageParams = {
  prompt: string;
  mimeType: string;
  modelId: string;
  label: string;
  fileUri: string;
};

async function renderImage(params: RenderImageParams): Promise<string | undefined> {
  return withRenderSlot(async () => {
    const { prompt, mimeType, modelId, label, fileUri } = params;
    if (!fileUri) throw new Error(`${label} requires fileUri input`);
    const docIdForAgent = label;
    for (let attempt = 1; attempt <= RENDER_RETRIES; attempt++) {
      try {
        const body = {
          contents: [
            {
              role: 'user',
              parts: [
                { text: prompt },
                { fileData: { fileUri, mimeType } },
              ],
            },
          ],
          generationConfig: {
            ...IMAGE_GEN_CONFIG,
            responseModalities: ['TEXT', 'IMAGE'],
          },
          safetySettings: IMAGE_SAFETY,
        };

        const url = `https://aiplatform.googleapis.com/v1/projects/${VERTEX_PROJECT}/locations/${IMAGE_REGION}/publishers/google/models/${modelId}:generateContent`;
        const token = await auth.getAccessToken();
        const res = await withTimeout(
          fetch(url, {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${token}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify(body),
          }),
          RENDER_TIMEOUT_MS,
          `${label}-fetch`
        );

        const resText = await res.text();
        if (res.status === 429) {
          throw Object.assign(new Error(`${label} received 429`), { status: 429, resText });
        }
        if (!res.ok) {
          throw Object.assign(new Error(`${label} failed status ${res.status}`), {
            status: res.status,
            statusText: res.statusText,
            resText: resText.slice(0, 400),
          });
        }

        let parsed: any;
        try {
          parsed = JSON.parse(resText);
        } catch (e) {
          throw Object.assign(new Error(`${label} response parse error`), { resText: resText.slice(0, 400) });
        }

        const imagePart =
          parsed?.candidates
            ?.flatMap((c: any) => c?.content?.parts ?? [])
            ?.find((p: any) => p?.inlineData?.data || p?.data);
        const imageB64: string | undefined = imagePart?.inlineData?.data ?? imagePart?.data;
        if (!imageB64) throw new Error(`${label} missing image`);
        return imageB64;
      } catch (err: any) {
        const status = err?.status ?? err?.response?.status;
        const message = `${err?.message ?? err}`;
        const isRetryable = status === 429 || message.includes('429') || message.includes('timed out');
        const attemptInfo = `${label} attempt ${attempt}/${RENDER_RETRIES}`;
        console.error(`${attemptInfo} genai error`, err);
        if (attempt >= RENDER_RETRIES || !isRetryable) {
          // Enqueue agent job for external worker to pick up if available.
          const queued = await enqueueAgentJob(label, prompt, fileUri, mimeType, modelId, docIdForAgent);
          if (queued) {
            const fromQueue = await waitForAgentJob(queued, label);
            if (fromQueue?.outputB64) return fromQueue.outputB64;
            if (fromQueue?.outputPath) {
              const { bucket, object } = parseGsUri(fromQueue.outputPath);
        const [url] = await storage.bucket(bucket).file(object).getSignedUrl({
          action: 'read',
          expires: Date.now() + 60 * 60 * 1000,
        });
        const buf = await fetch(url).then((r) => r.arrayBuffer());
        return Buffer.from(buf).toString('base64');
      }
          }
          return undefined;
        }
        // exponential backoff with jitter
        const backoff = RENDER_BASE_DELAY_MS * Math.pow(2, attempt - 1);
        const jitter = Math.floor(Math.random() * 1000);
        await delay(backoff + jitter);
      }
    }
    return undefined;
  });
}

type AgentJobDoc = {
  jobId: string;
  status: 'queued' | 'running' | 'done' | 'error';
  prompt: string;
  fileUri: string;
  mimeType: string;
  label: string;
  modelId: string;
  outputPath?: string;
  outputText?: string;
  error?: string;
  createdAt: number;
  updatedAt: number;
};

async function enqueueAgentJob(
  label: string,
  prompt: string,
  fileUri: string,
  mimeType: string,
  modelId: string,
  docId: string
): Promise<string | undefined> {
  try {
    const id = docId;
    const ref = firestore.collection(AGENT_QUEUE_COLLECTION).doc(id);
    const existing = await ref.get();
    if (existing.exists && existing.data()?.status !== 'error') {
      console.warn(`${label}: agent job ${id} already exists, reusing`);
      return id;
    }
    const now = Date.now();
    const payload: AgentJobDoc = {
      jobId: id,
      status: 'queued',
      prompt,
      fileUri,
      mimeType,
      label,
      modelId,
      createdAt: now,
      updatedAt: now,
    };
    await ref.set(payload, { merge: false });
    console.warn(`${label}: enqueued agent job ${id}`);
    return id;
  } catch (e) {
    console.error('enqueueAgentJob failed', e);
    return undefined;
  }
}

type AgentJobResult = { outputB64?: string; outputText?: string; outputPath?: string };

async function waitForAgentJob(docId: string, label: string): Promise<AgentJobResult | undefined> {
  const start = Date.now();
  while (Date.now() - start < AGENT_QUEUE_WAIT_MS) {
    const snap = await firestore.collection(AGENT_QUEUE_COLLECTION).doc(docId).get();
    if (!snap.exists) break;
    const data = snap.data() as AgentJobDoc;
    if (data.status === 'done' && (data.outputText || data.outputPath)) {
      console.log(`${label}: agent job ${docId} completed`);
      return { outputText: data.outputText, outputPath: data.outputPath };
    }
    if (data.status === 'error') {
      console.warn(`${label}: agent job ${docId} error ${data.error}`);
      return undefined;
    }
    await delay(3000);
  }
  console.warn(`${label}: agent job ${docId} timed out waiting for worker`);
  return undefined;
}
