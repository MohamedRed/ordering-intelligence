import 'dotenv/config';

import fs from 'node:fs';
import path from 'node:path';
import { spawn, ChildProcess } from 'node:child_process';

import { Firestore } from '@google-cloud/firestore';
import axios from 'axios';

const FIREBASE_API_KEY = process.env.FIREBASE_API_KEY ?? 'AIzaSyAyva47VFazHoIHMkQVJ7j9_preZIyFlvI';
const FIREBASE_USER = process.env.FIREBASE_USER ?? 'admin-tester@example.com';
const FIREBASE_PASS = process.env.FIREBASE_PASS ?? 'AdminTest123!';

async function main() {
  const worker = await startWorkerIfRequested();
  const baseUrl = reqEnv('MENU_INGESTION_BASE_URL');
  const restaurantId = reqEnv('MENU_INGESTION_RESTAURANT_ID');
  const samplePath = reqEnv('MENU_INGESTION_SAMPLE_PATH');
  const projectId = optEnv('GOOGLE_CLOUD_PROJECT') ?? optEnv('GCP_PROJECT');

  if (!fs.existsSync(samplePath)) {
    throw new Error(`Sample file not found at ${samplePath}`);
  }

  console.log('[start] requesting upload URLs');
  const startResp = await axios.post(`${baseUrl}/ingest/start`, {
    restaurantId,
    pageCount: 1,
  });

  if (!startResp.data?.uploadUrls || startResp.data.uploadUrls.length !== 1) {
    throw new Error(
      `ingest/start did not return expected uploadUrls (got ${startResp.data?.uploadUrls?.length ?? 0})`
    );
  }

  const jobId: string = startResp.data.jobId;
  const uploadUrl: string = startResp.data.uploadUrls[0];
  console.log('[upload] job', jobId);

  const fileBuf = fs.readFileSync(samplePath);
  await axios.put(uploadUrl, fileBuf, {
    headers: { 'Content-Type': inferMime(samplePath) },
    maxContentLength: Infinity,
    maxBodyLength: Infinity,
  });
  console.log('[upload] done');

  await axios.post(`${baseUrl}/ingest/submit`, { jobId });
  console.log('[submit] queued');

  // Allow longer processing because image generation may fall back to external worker.
  const maxAttempts = Number(process.env.MENU_INGESTION_STATUS_ATTEMPTS ?? 60); // ~10 min at 10s
  const status = await waitForReady(baseUrl, jobId, maxAttempts, 10_000);
  console.log('[status]', status.status);
  if (status.status !== 'ready') {
    throw new Error(`job did not reach ready state (status=${status.status})`);
  }

  console.log('[draft] validating thumbnails');
  await assertThumbnails(baseUrl, jobId);

  if (!projectId) {
    console.warn('No GOOGLE_CLOUD_PROJECT provided; skipping Firestore draft verification.');
  } else {
    const draft = await readDraft(projectId, jobId);
    console.log(`[draft] items: ${draft?.items?.length ?? 0}`);
  }

  const idToken = await getIdToken();
  await axios.post(
    `${baseUrl}/ingest/${jobId}/approve`,
    {},
    {
      headers: { Authorization: `Bearer ${idToken}` },
    }
  );
  console.log('[approve] published');

  if (projectId) {
    const published = await readPublished(projectId, restaurantId);
    console.log(`[publish] menu items in Firestore: ${published}`);
  }

  console.log('[done] job', jobId);
  await stopWorker(worker);
}

type JobStatus = { status: string };

async function waitForReady(baseUrl: string, jobId: string, attempts: number, delayMs: number) {
  for (let i = 0; i < attempts; i++) {
    const resp = await axios.get<JobStatus>(`${baseUrl}/ingest/${jobId}`);
    if (resp.data.status === 'ready' || resp.data.status === 'error') return resp.data;
    // keep waiting on 'processing' because external worker may be generating the image
    await new Promise((r) => setTimeout(r, delayMs));
  }
  throw new Error('Timed out waiting for job to be ready');
}

async function readDraft(projectId: string, jobId: string) {
  const firestore = new Firestore({ projectId });
  const snap = await firestore.collection('menus_drafts').doc(jobId).get();
  return snap.data();
}

async function readPublished(projectId: string, restaurantId: string): Promise<number> {
  const firestore = new Firestore({ projectId });
  const snap = await firestore.collection('restaurants').doc(restaurantId).collection('menus').count().get();
  return snap.data().count ?? 0;
}

async function getIdToken(): Promise<string> {
  const resp = await axios.post(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}`,
    {
      email: FIREBASE_USER,
      password: FIREBASE_PASS,
      returnSecureToken: true,
    }
  );
  return resp.data.idToken as string;
}

async function assertThumbnails(baseUrl: string, jobId: string) {
  const idToken = await getIdToken();
  const resp = await axios.get(`${baseUrl}/ingest/${jobId}/draft`, {
    headers: { Authorization: `Bearer ${idToken}` },
  });
  const items: any[] = resp.data?.draft?.items ?? [];
  const minItems = Number(process.env.MENU_INGESTION_MIN_ITEMS ?? 4);
  // Ensure composite was generated and returned
  const compositeUrls: string[] = resp.data?.draft?.compositeUrls ?? [];
  if (!compositeUrls.length) {
    throw new Error('Missing composite image (draft.compositeUrls is empty)');
  }
  const detected = Number(resp.data?.draft?.detectedItemCount ?? 0);
  if (detected && detected < minItems) {
    throw new Error(`Composite detection found only ${detected} items (<${minItems})`);
  }
  if (!detected) {
    console.warn(`[draft] no detectedItemCount; skipping min-items check (requested ${minItems})`);
  }

  const missing = items.filter((it) => !it.photoUrl && !it.imageUrl).map((it) => it.name ?? 'unnamed');
  if (missing.length) {
    throw new Error(`Missing thumbnails for items: ${missing.join(', ')}`);
  }
  console.log(`[draft] thumbnails ok (${items.length} items), composites: ${compositeUrls.length}`);
}

function inferMime(p: string): string {
  const ext = path.extname(p).toLowerCase();
  if (ext === '.png') return 'image/png';
  if (ext === '.jpg' || ext === '.jpeg') return 'image/jpeg';
  if (ext === '.pdf') return 'application/pdf';
  return 'application/octet-stream';
}

function reqEnv(name: string): string {
  const val = process.env[name];
  if (!val) throw new Error(`Missing env ${name}`);
  return val;
}

function optEnv(name: string): string | undefined {
  return process.env[name];
}

async function startWorkerIfRequested(): Promise<ChildProcess | undefined> {
  if (process.env.MENU_INGESTION_START_WORKER !== '1') return undefined;
  await cleanQueuedAgentJobs();
  const workerPath = resolveWorkerPath();
  if (!workerPath) {
    console.warn('[worker] skip: could not resolve agent_worker.js path');
    return undefined;
  }
  console.log('[worker] starting', workerPath);
  const proc = spawn('node', [workerPath], {
    env: { ...process.env },
    stdio: 'inherit',
  });
  return proc;
}

async function stopWorker(proc?: ChildProcess) {
  if (!proc) return;
  console.log('[worker] stopping');
  proc.kill('SIGTERM');
}

function resolveWorkerPath(): string | undefined {
  const candidates = [
    process.env.MENU_INGESTION_WORKER_PATH,
    path.resolve(__dirname, '../../../backend/services/menu-ingestion/scripts/agent_worker.js'),
    path.resolve(process.cwd(), '../backend/services/menu-ingestion/scripts/agent_worker.js'),
    path.resolve(process.cwd(), '../../backend/services/menu-ingestion/scripts/agent_worker.js'),
    path.resolve(process.cwd(), 'backend/services/menu-ingestion/scripts/agent_worker.js'),
  ].filter(Boolean) as string[];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return undefined;
}

async function cleanQueuedAgentJobs() {
  try {
    const projectId = optEnv('GOOGLE_CLOUD_PROJECT') ?? optEnv('GCP_PROJECT');
    if (!projectId) return;
    const collection = process.env.AGENT_QUEUE_COLLECTION || 'agent_jobs';
    const firestore = new Firestore({ projectId });
    const snap = await firestore.collection(collection).where('status', '==', 'queued').limit(200).get();
    if (!snap.empty) {
      const batch = firestore.batch();
      snap.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
      console.log(`[worker] cleared queued agent jobs: ${snap.size}`);
    }
  } catch (e) {
    console.warn('[worker] failed to clear queued jobs', e);
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
