import { Storage } from '@google-cloud/storage';
import { GoogleAuth } from 'google-auth-library';
import {
  bucketEnv as BUCKET_ENV,
  AGENT_ANALYSIS_URL,
  ANALYSIS_MODEL,
} from '../config.js';
import { assertFilesWithinPageLimit } from '../ingestion_limits.js';
import { slugifyName } from '../utils.js';
import type { MenuItem } from '../types.js';
import { enqueueAgentJob, waitForAgentJob } from './agent_queue.js';
import { fetchGradio } from './gradio_client.js';
import {
  failWorkflowNode,
  finishWorkflowNode,
  startWorkflowNode,
} from './workflow.js';

const storage = new Storage();
const BUCKET = (BUCKET_ENV || '') as string;
const auth = new GoogleAuth({ scopes: 'https://www.googleapis.com/auth/cloud-platform' });

export async function analyzeMenuFromOriginal(
  files: string[],
  jobId?: string,
): Promise<MenuItem[]> {
  assertFilesWithinPageLimit(files);
  const results: MenuItem[] = [];
  let page = 0;
  for (const object of files) {
    page += 1;
    const fileUri = `gs://${BUCKET}/${object}`;
    const nodeId = jobId ? `analysis_p${page}` : undefined;
    if (jobId && nodeId) {
      await startWorkflowNode(jobId, {
        id: nodeId,
        parentId: 'root',
        kind: 'analysis',
        label: `Analyze page ${page}`,
        modelId: ANALYSIS_MODEL,
        fileUri,
        page,
        seq: 1000 + page,
      });
    }
    let parsed = await analyzeOriginalViaVertex(fileUri, 'image/jpeg');
    if ((!parsed || !parsed.length) && AGENT_ANALYSIS_URL) {
      parsed = await analyzeOriginalViaAgent(fileUri);
    }
    appendParsedItems(results, parsed);
    if (jobId && nodeId) {
      if (parsed && Array.isArray(parsed) && parsed.length) {
        await finishWorkflowNode(jobId, nodeId, { meta: { items: parsed.length } });
      } else {
        await failWorkflowNode(jobId, nodeId, 'no items found');
      }
    }
  }
  return results;
}

function appendParsedItems(results: MenuItem[], parsed: any): void {
  if (!Array.isArray(parsed)) return;
  for (const it of parsed) {
    if (!it?.name) continue;
    results.push({
      id: it.id ?? slugifyName(it.name),
      name: it.name,
      category: it.category ?? undefined,
      description: it.description ?? undefined,
      price: typeof it.price === 'number' ? it.price : undefined,
      currency: it.currency ?? undefined,
      sizes: Array.isArray(it.sizes)
        ? it.sizes.map((s: any) => String(s ?? '').trim()).filter(Boolean)
        : undefined,
      modifiers: Array.isArray(it.modifiers)
        ? it.modifiers.map((s: any) => String(s ?? '').trim()).filter(Boolean)
        : undefined,
      available: it.available ?? true,
      imageUrl: undefined,
      photoUrl: undefined,
    });
  }
}

async function analyzeOriginalViaVertex(fileUri: string, mimeType: string): Promise<any[]> {
  const prompt =
    'Read this menu page image and return a strict JSON array of menu items. ' +
    'Use ONLY visible text. Do NOT invent items, modifiers, sizes, or combo contents. ' +
    'Return array items with shape:\n' +
    '[{\n' +
    '  "id": string (stable, slug-like; if missing, omit and we will derive),\n' +
    '  "name": string,\n' +
    '  "category": string (optional),\n' +
    '  "description": string (optional),\n' +
    '  "price": number (optional, in major units like 5.99),\n' +
    '  "currency": "USD"|"EUR"|"GBP" (optional; map symbols $,€,£),\n' +
    '  "available": boolean (optional; default true),\n' +
    '  "sizes": string[] (optional; e.g. ["Small","Large"] if sizes are explicitly listed),\n' +
    '  "modifiers": string[] (optional; flat list of explicitly listed options like toppings/sauces)\n' +
    '}]\n' +
    'If a field is not visible, omit it. Output JSON only.';
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

  const url = `https://aiplatform.googleapis.com/v1/projects/${process.env.GOOGLE_CLOUD_PROJECT}/locations/global/publishers/google/models/${ANALYSIS_MODEL}:generateContent`;

  try {
    const token = await auth.getAccessToken();
    const controller = new AbortController();
    const timeout = setTimeout(
      () => controller.abort(),
      Number(process.env.GEN_TIMEOUT_MS ?? 120_000),
    );
    let res: any;
    let resText = '';
    try {
      res = await fetch(url, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      resText = await res.text();
    } finally {
      clearTimeout(timeout);
    }
    const contentType = res.headers.get('content-type') || '';
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
      console.error('analyze-original response parse error', {
        message: (e as Error).message,
        resText: resText.slice(0, 200),
      });
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
    console.error('analyze-original error', err);
    const docId = `analysis-${slugifyName(fileUri)}-${Buffer.from(fileUri).toString('base64').slice(0, 8)}`;
    const queued = await enqueueAgentJob('analysis', prompt, fileUri, mimeType, ANALYSIS_MODEL, docId);
    if (!queued) return [];
    const res = await waitForAgentJob(queued, 'analysis');
    const text = res?.outputText;
    if (!text) return [];
    try {
      const parsed = JSON.parse(text);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }
}

async function analyzeOriginalViaAgent(fileUri: string): Promise<any[]> {
  if (!AGENT_ANALYSIS_URL) return [];
  try {
    const [signedUrl] = await storage
      .bucket(BUCKET)
      .file(fileUri.replace(`gs://${BUCKET}/`, ''))
      .getSignedUrl({
        action: 'read',
        expires: Date.now() + 15 * 60 * 1000,
      });
    const res = await fetchGradio(
      AGENT_ANALYSIS_URL,
      'Extract menu items as strict JSON array with fields [{id,name,category,description,price,currency,available,sizes,modifiers}]. Use only visible text; do not invent.',
      signedUrl,
    );
    if (!res?.text) return [];
    try {
      const arr = JSON.parse(res.text);
      return Array.isArray(arr) ? arr : [];
    } catch {
      return [];
    }
  } catch (err) {
    console.error('analyzeOriginalViaAgent error', err);
    return [];
  }
}
