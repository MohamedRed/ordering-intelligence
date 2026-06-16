import { GoogleAuth } from 'google-auth-library';
import { VertexAI } from '@google-cloud/vertexai';
import { Storage } from '@google-cloud/storage';
import {
  VERTEX_PROJECT,
  IMAGE_REGION,
  COMPOSITE_MODEL,
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
  LOG_GENAI_SUCCESS,
} from '../config.js';
import { delay, parseGsUri } from '../utils.js';
import { enqueueAgentJob, waitForAgentJob } from './agent_queue.js';

const storage = new Storage();
const auth = new GoogleAuth({ scopes: 'https://www.googleapis.com/auth/cloud-platform' });
const vertexText = new VertexAI({
  project: VERTEX_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || 'ordering-intelligence',
  location: IMAGE_REGION,
});
const textModel = (modelId: string) => vertexText.getGenerativeModel({ model: modelId });

// Serialize Gemini image calls to avoid 429 bursts.
let renderLock: Promise<void> = Promise.resolve();
let lastRenderStart = 0;

// GCS downloads for agent-worker outputs can occasionally hang; keep them bounded.
const GCS_READ_TIMEOUT_MS = Number(process.env.GCS_READ_TIMEOUT_MS ?? 30_000);
async function withRenderSlot<T>(fn: () => Promise<T>): Promise<T> {
  const prev = renderLock;
  let release: () => void = () => {};
  renderLock = new Promise<void>((resolve) => {
    release = resolve;
  });
  await prev;
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
function vlog(...args: any[]) {
  if (LOG_GENAI_SUCCESS) console.log(...args);
}

const IMAGE_GEN_CONFIG: any = {
  maxOutputTokens: 32768,
  temperature: 1,
  topP: 0.95,
  responseModalities: ['TEXT', 'IMAGE'],
  imageConfig: {
    aspectRatio: '1:1',
    imageSize: '1K',
  },
};

const IMAGE_SAFETY: any[] = [
  { category: 'HARM_CATEGORY_HATE_SPEECH', threshold: 'OFF' },
  { category: 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold: 'OFF' },
  { category: 'HARM_CATEGORY_SEXUALLY_EXPLICIT', threshold: 'OFF' },
  { category: 'HARM_CATEGORY_HARASSMENT', threshold: 'OFF' },
];

export async function renderImage(params: {
  prompt: string;
  mimeType: string;
  modelId: string;
  label: string;
  fileUri: string;
}): Promise<string | undefined> {
  return withRenderSlot(async () => {
    const { prompt, mimeType, modelId, label, fileUri } = params;
    if (!fileUri) throw new Error(`${label} requires fileUri input`);
    const docIdForAgent = buildAgentDocId(label, fileUri);
    const start = Date.now();
    for (let attempt = 1; attempt <= RENDER_RETRIES; attempt++) {
      try {
        // Important: make sure both the request *and* reading the response body are bounded.
        // We previously timed out only the fetch() promise, but res.text() could hang indefinitely.
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), RENDER_TIMEOUT_MS);
        const attemptStart = Date.now();

        let res: any;
        let resText = '';
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
        vlog('genai render success', { label, modelId, attempt, ms: Date.now() - start, attemptMs: Date.now() - attemptStart });
        return imageB64;
      } catch (err: any) {
        const status = err?.status ?? err?.response?.status;
        const message = `${err?.message ?? err}`;
        const isAbort = err?.name === 'AbortError' || message.toLowerCase().includes('aborted');
        const isRetryable = status === 429 || message.includes('429') || message.includes('timed out') || isAbort;
        const attemptInfo = `${label} attempt ${attempt}/${RENDER_RETRIES}`;
        console.error(`${attemptInfo} genai error`, err);
        if (attempt >= RENDER_RETRIES || !isRetryable) {
          const queued = await enqueueAgentJob(label, prompt, fileUri, mimeType, modelId, docIdForAgent);
          if (queued) {
            const fromQueue = await waitForAgentJob(queued, label);
            if (fromQueue?.outputB64) return fromQueue.outputB64;
            if (fromQueue?.outputPath) {
              const { bucket, object } = parseGsUri(fromQueue.outputPath);
              // Avoid signed URLs for internal reads (signed URLs require service-account style creds with client_email).
              // Direct download works with any ADC that can read the object.
              try {
                const [buf] = await withTimeout(
                  storage.bucket(bucket).file(object).download(),
                  GCS_READ_TIMEOUT_MS,
                  `${label}-gcs-download`,
                );
              return Buffer.from(buf).toString('base64');
              } catch (e) {
                console.warn(`${label}: agent output download failed`, { error: String((e as any)?.message ?? e) });
                return undefined;
              }
            }
          }
          return undefined;
        }
        const backoff = RENDER_BASE_DELAY_MS * Math.pow(2, attempt - 1);
        const jitter = Math.floor(Math.random() * 1000);
        await delay(backoff + jitter);
      }
    }
    return undefined;
  });
}

export async function geminiImage(prompt: string, fileUri: string, mimeType: string): Promise<Buffer | undefined> {
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

export async function geminiJson(
  prompt: string,
  fileUri: string,
  mimeType: string,
  modelId: string,
  label = 'analysis-json'
): Promise<any> {
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

  const url = `https://aiplatform.googleapis.com/v1/projects/${VERTEX_PROJECT}/locations/${IMAGE_REGION}/publishers/google/models/${modelId}:generateContent`;

  let resText = '';
  let lastErr: any;
  const start = Date.now();
  try {
    const token = await auth.getAccessToken();
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), GEN_TIMEOUT_MS);
    let res: any;
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
      console.error('analysis-json fetch failed', {
        status: res.status,
        statusText: res.statusText,
        bodySnippet: resText.slice(0, 400),
        contentType,
      });
      throw Object.assign(new Error(`${label} failed status ${res.status}`), { status: res.status });
    }
  } catch (err) {
    lastErr = err;
    console.error(`${label} error`, err);
    // Agent fallback
    const docId = buildAgentDocId(label, fileUri);
    const queued = await enqueueAgentJob(label, prompt, fileUri, mimeType, modelId, docId);
    if (queued) {
      const res = await waitForAgentJob(queued, label);
      const text = res?.outputText;
      if (text) {
        try {
          return JSON.parse(text);
        } catch {
          return undefined;
        }
      }
      if (res?.outputPath) {
        // If agent produced a file, try to read it as JSON.
        try {
          const { bucket, object } = parseGsUri(res.outputPath);
          // Avoid signed URLs for internal reads (signed URLs require service-account style creds with client_email).
          const [buf] = await storage.bucket(bucket).file(object).download();
          const jsonText = Buffer.from(buf).toString('utf8');
          return JSON.parse(jsonText);
        } catch {
          return undefined;
        }
      }
    }
    throw lastErr;
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
    console.warn('gemini json missing text', { model: modelId, raw: parsedResp });
    return undefined;
  }
  try {
    const parsed = JSON.parse(text);
    vlog('genai json success', { label, modelId, ms: Date.now() - start });
    return parsed;
  } catch (e) {
    console.error('gemini json parse error', e);
    return undefined;
  }
}

export async function geminiJsonText(
  prompt: string,
  modelId: string,
  label = 'analysis-json-text'
): Promise<any> {
  const body = {
    contents: [
      {
        role: 'user',
        parts: [{ text: prompt }],
      },
    ],
    generationConfig: {
      responseMimeType: 'application/json',
      temperature: 0.1,
    },
  };

  const url = `https://aiplatform.googleapis.com/v1/projects/${VERTEX_PROJECT}/locations/${IMAGE_REGION}/publishers/google/models/${modelId}:generateContent`;
  let resText = '';
  const start = Date.now();
  try {
    const token = await auth.getAccessToken();
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), GEN_TIMEOUT_MS);
    let res: any;
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
      console.error('analysis-json-text fetch failed', {
        status: res.status,
        statusText: res.statusText,
        bodySnippet: resText.slice(0, 400),
        contentType,
      });
      throw Object.assign(new Error(`${label} failed status ${res.status}`), { status: res.status });
    }
  } catch (err) {
    console.error(`${label} error`, err);
    throw err;
  }

  let parsedResp: any;
  try {
    parsedResp = JSON.parse(resText);
  } catch (e) {
    console.error('analysis-json-text response parse error', {
      message: (e as Error).message,
      resText: resText.slice(0, 200),
    });
    return undefined;
  }

  const text =
    parsedResp?.candidates
      ?.flatMap((c: any) => c?.content?.parts ?? [])
      ?.find((p: any) => p?.text)?.text;
  if (!text) {
    console.warn('gemini json text missing text', { model: modelId, raw: parsedResp });
    return undefined;
  }
  try {
    const parsed = JSON.parse(text);
    vlog('genai json text success', { label, modelId, ms: Date.now() - start });
    return parsed;
  } catch (e) {
    console.error('gemini json text parse error', e);
    return undefined;
  }
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

function buildAgentDocId(label: string, fileUri: string): string {
  try {
    const { object } = parseGsUri(fileUri);
    const clean = object.replace(/[^a-zA-Z0-9-_]/g, '_').slice(0, 40);
    return `${label}-${clean || 'doc'}`;
  } catch {
    return `${label}-${Date.now()}`;
  }
}
