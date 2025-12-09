import 'dotenv/config';

import { Firestore } from '@google-cloud/firestore';
import { Storage } from '@google-cloud/storage';
import { spawn } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';

const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || process.env.GCP_PROJECT;
const BUCKET =
  process.env.STORAGE_BUCKET_MENUS || process.env.MENU_BUCKET || 'ordering-intelligence-menus-dev';
const COLLECTION = process.env.AGENT_QUEUE_COLLECTION || 'agent_jobs';
const CONFIG_DOC = process.env.AGENT_CONFIG_DOC || 'agent_worker/config';
const MODEL_ID = process.env.MODEL_ID || 'gemini-3-pro-image-preview';
const WORKER_LABEL = process.env.WORKER_LABEL || 'smoke';
const SAMPLE = process.env.AGENT_SAMPLE_PATH || path.resolve(__dirname, '../../fixtures/menus/fwencheese_menu_1.jpg');
const MIME = 'image/jpeg';

if (!PROJECT) throw new Error('GOOGLE_CLOUD_PROJECT required');

async function main() {
  const firestore = new Firestore({ projectId: PROJECT });
  const storage = new Storage({ projectId: PROJECT });

  // Ensure worker is enabled
  await firestore.doc(CONFIG_DOC).set({ enabled: true, updatedAt: Date.now() }, { merge: true });
  console.log('[smoke] worker enabled flag set');

  // Clean old queued jobs to avoid interference
  const old = await firestore
    .collection(COLLECTION)
    .where('status', '==', 'queued')
    .where('label', '==', WORKER_LABEL)
    .limit(100)
    .get();
  for (const doc of old.docs) {
    await doc.ref.delete();
  }
  if (!old.empty) console.log('[smoke] cleared queued jobs', old.size);

  const object = `agent-smoke/${Date.now()}.jpg`;
  await storage.bucket(BUCKET).upload(SAMPLE, { destination: object, contentType: MIME, resumable: false });
  const fileUri = `gs://${BUCKET}/${object}`;
  console.log('[smoke] uploaded sample to', fileUri);

  const docId = `smoke-${Date.now()}`;
  const prompt = 'Generate a composite of items on this menu page.';
  const docRef = firestore.collection(COLLECTION).doc(docId);

  await docRef.set({
    jobId: docId,
    status: 'queued',
    prompt,
    fileUri,
    mimeType: MIME,
    label: WORKER_LABEL,
    modelId: MODEL_ID,
    createdAt: Date.now(),
    updatedAt: Date.now(),
  });
  console.log('[smoke] enqueued job', docId);

  const worker = spawn('node', [workerPath()], { env: { ...process.env }, stdio: 'inherit' });
  console.log('[smoke] worker pid', worker.pid);

  const deadline = Date.now() + 120_000;
  while (Date.now() < deadline) {
    const snap = await docRef.get();
    if (!snap.exists) throw new Error('agent job doc missing');
    const data = snap.data()!;
    console.log('[smoke] poll', { status: data.status, outputPath: data.outputPath, outputText: !!data.outputText });
    if (data.status === 'done' && (data.outputPath || data.outputText)) {
      console.log('[smoke] success', { outputPath: data.outputPath, hasText: !!data.outputText });
      worker.kill('SIGTERM');
      process.exit(0);
    }
    if (data.status === 'error') {
      worker.kill('SIGTERM');
      throw new Error(`worker error: ${data.error}`);
    }
    await sleep(3000);
  }
  worker.kill('SIGTERM');
  throw new Error('smoke test timed out waiting for agent worker');
}

function workerPath(): string {
  const candidates = [
    process.env.MENU_INGESTION_WORKER_PATH,
    path.resolve(__dirname, '../../../backend/services/menu-ingestion/scripts/agent_worker.js'),
  ].filter(Boolean) as string[];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  throw new Error('agent_worker.js not found; set MENU_INGESTION_WORKER_PATH');
}

function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
