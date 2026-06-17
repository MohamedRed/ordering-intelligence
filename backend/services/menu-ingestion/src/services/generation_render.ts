import {
  RENDER_BASE_DELAY_MS,
  RENDER_MIN_INTERVAL_MS,
  RENDER_MODEL,
  RENDER_RETRIES,
  RENDER_TIMEOUT_MS,
} from '../config.js';
import { delay } from '../utils.js';
import { queueImageAgentFallback } from './generation_agent_outputs.js';
import {
  buildAgentDocId,
  fetchVertexContent,
  vlog,
} from './generation_shared.js';

export type RenderImageParams = {
  prompt: string;
  mimeType: string;
  modelId: string;
  label: string;
  fileUri: string;
};

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

let renderLock: Promise<void> = Promise.resolve();
let lastRenderStart = 0;

export async function renderImage(
  params: RenderImageParams,
): Promise<string | undefined> {
  return withRenderSlot(async () => runRenderImage(params));
}

export async function geminiImage(
  prompt: string,
  fileUri: string,
  mimeType: string,
): Promise<Buffer | undefined> {
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

async function runRenderImage(params: RenderImageParams): Promise<string | undefined> {
  const { prompt, mimeType, modelId, label, fileUri } = params;
  if (!fileUri) throw new Error(`${label} requires fileUri input`);

  const docIdForAgent = buildAgentDocId(label, fileUri);
  const start = Date.now();
  for (let attempt = 1; attempt <= RENDER_RETRIES; attempt += 1) {
    try {
      const attemptStart = Date.now();
      const body = buildImageBody(prompt, fileUri, mimeType);
      const { res, resText } = await fetchVertexContent({
        modelId,
        body,
        timeoutMs: RENDER_TIMEOUT_MS,
      });

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

      const imageB64 = parseImageResponse(label, resText);
      vlog('genai render success', {
        label,
        modelId,
        attempt,
        ms: Date.now() - start,
        attemptMs: Date.now() - attemptStart,
      });
      return imageB64;
    } catch (err: any) {
      if (await shouldFinishWithAgent(params, docIdForAgent, attempt, err)) {
        return queueImageAgentFallback({ ...params, docId: docIdForAgent });
      }
      await waitBeforeRetry(attempt);
    }
  }
  return undefined;
}

async function withRenderSlot<T>(fn: () => Promise<T>): Promise<T> {
  const prev = renderLock;
  let release: () => void = () => {};
  renderLock = new Promise<void>((resolve) => {
    release = resolve;
  });
  await prev;
  const since = Date.now() - lastRenderStart;
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

function buildImageBody(prompt: string, fileUri: string, mimeType: string): Record<string, unknown> {
  return {
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
}

function parseImageResponse(label: string, resText: string): string {
  let parsed: any;
  try {
    parsed = JSON.parse(resText);
  } catch {
    throw Object.assign(new Error(`${label} response parse error`), {
      resText: resText.slice(0, 400),
    });
  }

  const imagePart = parsed?.candidates
    ?.flatMap((candidate: any) => candidate?.content?.parts ?? [])
    ?.find((part: any) => part?.inlineData?.data || part?.data);
  const imageB64: string | undefined = imagePart?.inlineData?.data ?? imagePart?.data;
  if (!imageB64) throw new Error(`${label} missing image`);
  return imageB64;
}

async function shouldFinishWithAgent(
  params: RenderImageParams,
  docIdForAgent: string,
  attempt: number,
  err: any,
): Promise<boolean> {
  const status = err?.status ?? err?.response?.status;
  const message = `${err?.message ?? err}`;
  const isAbort = err?.name === 'AbortError' || message.toLowerCase().includes('aborted');
  const isRetryable = status === 429 || message.includes('429') || message.includes('timed out') || isAbort;
  const attemptInfo = `${params.label} attempt ${attempt}/${RENDER_RETRIES}`;
  console.error(`${attemptInfo} genai error`, err);
  return attempt >= RENDER_RETRIES || !isRetryable || !docIdForAgent;
}

async function waitBeforeRetry(attempt: number): Promise<void> {
  const backoff = RENDER_BASE_DELAY_MS * Math.pow(2, attempt - 1);
  const jitter = Math.floor(Math.random() * 1000);
  await delay(backoff + jitter);
}
