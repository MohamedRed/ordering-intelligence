import { Firestore } from '@google-cloud/firestore';
import {
  AGENT_QUEUE_COLLECTION,
  AGENT_QUEUE_WAIT_MS,
} from '../config.js';
import { delay } from '../utils.js';

export type AgentJobDoc = {
  jobId: string;
  status: 'queued' | 'running' | 'done' | 'error' | 'canceled';
  prompt: string;
  fileUri: string;
  mimeType: string;
  label: string;
  modelId: string;
  parentIngestJobId?: string;
  parentRestaurantId?: string;
  outputPath?: string;
  outputText?: string;
  error?: string;
  createdAt: number;
  updatedAt: number;
};

export type AgentJobResult = { outputB64?: string; outputText?: string; outputPath?: string };

const firestore = new Firestore({ ignoreUndefinedProperties: true });

function inferParentFromFileUri(fileUri: string): { parentIngestJobId?: string; parentRestaurantId?: string } {
  // Expected: gs://<bucket>/menu-raw/<restaurantId>/<jobId>/page-1.jpg
  // Also allow URLs that contain /menu-raw/<restaurantId>/<jobId>/...
  const raw = String(fileUri || '');
  const idx = raw.indexOf('/menu-raw/');
  if (idx === -1) return {};
  const tail = raw.slice(idx + '/menu-raw/'.length);
  const parts = tail.split('/').filter(Boolean);
  if (parts.length < 2) return {};
  const [restaurantId, jobId] = parts;
  if (!restaurantId || !jobId) return {};
  return { parentRestaurantId: restaurantId, parentIngestJobId: jobId };
}

export async function enqueueAgentJob(
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
    const parent = inferParentFromFileUri(fileUri);
    const payload: AgentJobDoc = {
      jobId: id,
      status: 'queued',
      prompt,
      fileUri,
      mimeType,
      label,
      modelId,
      ...parent,
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

export async function waitForAgentJob(docId: string, label: string): Promise<AgentJobResult | undefined> {
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
    if (data.status === 'canceled') {
      console.warn(`${label}: agent job ${docId} canceled`);
      return undefined;
    }
    await delay(3000);
  }
  console.warn(`${label}: agent job ${docId} timed out waiting for worker`);
  return undefined;
}
