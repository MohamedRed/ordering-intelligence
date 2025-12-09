// Agent worker: polls Firestore for queued agent jobs and fulfills them by calling Vertex directly
// using the same pattern as scripts/single_composite.js (no Gradio agent).
//
// Usage:
//   GOOGLE_CLOUD_PROJECT=ordering-intelligence \
//   GOOGLE_APPLICATION_CREDENTIALS=~/path/key.json \
//   MODEL_ID=gemini-3-pro-image-preview \
//   node scripts/agent_worker.js

import { Firestore } from '@google-cloud/firestore';
import { Storage } from '@google-cloud/storage';
import { GoogleAuth } from 'google-auth-library';
import fetch from 'node-fetch';

const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || process.env.GCP_PROJECT;
const BUCKET = process.env.STORAGE_BUCKET_MENUS || process.env.MENU_BUCKET || 'ordering-intelligence-menus-dev';
const COLLECTION = process.env.AGENT_QUEUE_COLLECTION || 'agent_jobs';
const POLL_MS = Number(process.env.AGENT_WORKER_POLL_MS || 3000);
const MAX_ATTEMPTS = Number(process.env.AGENT_WORKER_ATTEMPTS || 3);
const MODEL_ID = process.env.MODEL_ID || 'gemini-3-pro-image-preview';
const LOCATION = process.env.IMAGE_REGION || 'global';
const CONFIG_DOC = process.env.AGENT_CONFIG_DOC || 'agent_worker/config';
const WORKER_LABEL = process.env.WORKER_LABEL;
const DEFAULT_BUCKET = process.env.STORAGE_BUCKET_MENUS || process.env.MENU_BUCKET;

if (!PROJECT) throw new Error('GOOGLE_CLOUD_PROJECT required');

const firestore = new Firestore({ projectId: PROJECT });
const storage = new Storage({ projectId: PROJECT });
const auth = new GoogleAuth({ scopes: 'https://www.googleapis.com/auth/cloud-platform' });

async function main() {
  console.log('[worker] starting', { collection: COLLECTION, model: MODEL_ID });
  let lastEnabled = undefined;
  while (true) {
    const enabled = await isEnabled();
    if (enabled !== lastEnabled) {
      console.log('[worker] enabled:', enabled);
      lastEnabled = enabled;
    }
    if (!enabled) {
      await sleep(POLL_MS);
      continue;
    }
    try {
      let query = firestore.collection(COLLECTION).where('status', '==', 'queued');
      if (WORKER_LABEL) query = query.where('label', '==', WORKER_LABEL);
      const snap = await query.limit(1).get();
      if (snap.empty) {
        await sleep(POLL_MS);
        continue;
      }
      const doc = snap.docs[0];
      await processJob(doc.id, doc.data());
    } catch (e) {
      console.error('[worker] poll error', e);
      await sleep(POLL_MS);
    }
  }
}

async function isEnabled() {
  try {
    const doc = await firestore.doc(CONFIG_DOC).get();
    if (!doc.exists) return false;
    return Boolean(doc.data()?.enabled);
  } catch {
    return false;
  }
}

async function processJob(id, data) {
  console.log('[worker] processing', id);
  await update(id, { status: 'running', updatedAt: Date.now() });
  const { fileUri, prompt, mimeType } = data;
  const modelId = data.modelId || MODEL_ID;
  if (WORKER_LABEL && data.label && data.label !== WORKER_LABEL) {
    console.warn('[worker] skipping job with label', data.label);
    await update(id, { status: 'error', error: 'skipped by label filter', updatedAt: Date.now() });
    return;
  }
  try {
    const fileData = await ensureSigned(fileUri);
    let attempt = 0;
    let result;
    while (attempt < MAX_ATTEMPTS && !result) {
      attempt++;
      result = await callVertex(prompt, fileData, mimeType || 'image/jpeg', modelId);
      if (!result) {
        const backoff = 5000 * attempt;
        console.warn(`[worker] attempt ${attempt} failed, backing off ${backoff}ms`);
        await sleep(backoff);
      }
    }
    if (!result?.b64 && !result?.text) throw new Error('vertex returned no data');
    let outputPath;
    if (result?.b64) {
      outputPath = await saveToGcs(id, result.b64, data.label);
    }
    await update(id, {
      status: 'done',
      outputPath,
      outputText: result?.text,
      updatedAt: Date.now(),
    });
    console.log('[worker] done', id);
  } catch (e) {
    console.error('[worker] error', id, e);
    await update(id, { status: 'error', error: String(e), updatedAt: Date.now() });
  }
}

async function callVertex(prompt, fileUri, mimeType, modelId) {
  const token = await auth.getAccessToken();
  const url = `https://aiplatform.googleapis.com/v1/projects/${PROJECT}/locations/${LOCATION}/publishers/google/models/${modelId}:generateContent`;
  const body = {
    contents: [
      {
        role: 'user',
        parts: [{ text: prompt }, { fileData: { fileUri, mimeType } }],
      },
    ],
    generationConfig: {
      responseModalities: ['TEXT', 'IMAGE'],
      maxOutputTokens: 32768,
      temperature: 1,
      topP: 0.95,
      imageConfig: {
        aspectRatio: '1:1',
        imageSize: '1K',
      },
    },
    safetySettings: [
      { category: 'HARM_CATEGORY_HATE_SPEECH', threshold: 'OFF' },
      { category: 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold: 'OFF' },
      { category: 'HARM_CATEGORY_SEXUALLY_EXPLICIT', threshold: 'OFF' },
      { category: 'HARM_CATEGORY_HARASSMENT', threshold: 'OFF' },
    ],
  };

  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) {
    console.warn('[vertex] non-200', res.status, res.statusText, text.slice(0, 200));
    return undefined;
  }
  try {
    const parsed = JSON.parse(text);
    const parts = parsed?.candidates?.flatMap((c) => c?.content?.parts ?? []) ?? [];
    const imagePart = parts.find((p) => p?.inlineData?.data || p?.data);
    const textPart = parts.find((p) => p?.text);
    return {
      b64: imagePart?.inlineData?.data ?? imagePart?.data,
      text: textPart?.text,
    };
  } catch (e) {
    console.warn('[vertex] parse error', e, text.slice(0, 200));
    return undefined;
  }
}

async function saveToGcs(id, b64, label) {
  const dest =
    label && label.includes('render')
      ? `menu-generated/agent-${id}.png`
      : `agent-output/${id}.png`;
  const buf = Buffer.from(b64, 'base64');
  await storage.bucket(BUCKET).file(dest).save(buf, {
    contentType: 'image/png',
    resumable: false,
  });
  return `gs://${BUCKET}/${dest}`;
}

async function ensureSigned(fileUri) {
  if (!fileUri || typeof fileUri !== 'string') {
    throw new Error('missing fileUri');
  }
  if (!fileUri.startsWith('gs://')) return fileUri;
  const trimmed = fileUri.replace(/^gs:\/\//, '');
  const [bucketRaw, ...rest] = trimmed.split('/');
  const bucket = bucketRaw || DEFAULT_BUCKET;
  if (!bucket) throw new Error('missing bucket in fileUri');
  const object = rest.join('/');
  try {
    const [url] = await storage.bucket(bucket).file(object).getSignedUrl({
      action: 'read',
      expires: Date.now() + 15 * 60 * 1000,
    });
    return url;
  } catch (e) {
    console.warn('[worker] signed URL failed, falling back to gs://', { error: String(e) });
    return fileUri; // let Vertex read directly with current creds
  }
}

async function update(id, patch) {
  await firestore.collection(COLLECTION).doc(id).set(patch, { merge: true });
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
