import { GoogleAuth } from 'google-auth-library';
import {
  IMAGE_REGION,
  LOG_GENAI_SUCCESS,
  VERTEX_PROJECT,
} from '../config.js';
import { parseGsUri } from '../utils.js';

const auth = new GoogleAuth({ scopes: 'https://www.googleapis.com/auth/cloud-platform' });

export type VertexContentResponse = {
  res: any;
  resText: string;
  contentType: string;
};

export async function fetchVertexContent(params: {
  modelId: string;
  body: Record<string, unknown>;
  timeoutMs: number;
}): Promise<VertexContentResponse> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), params.timeoutMs);
  try {
    const token = await auth.getAccessToken();
    const res = await fetch(vertexGenerateContentUrl(params.modelId), {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(params.body),
      signal: controller.signal,
    });
    const resText = await res.text();
    const contentType = res.headers?.get?.('content-type') || '';
    return { res, resText, contentType };
  } finally {
    clearTimeout(timeout);
  }
}

export function extractGeminiText(parsedResp: any): string | undefined {
  return parsedResp?.candidates
    ?.flatMap((candidate: any) => candidate?.content?.parts ?? [])
    ?.find((part: any) => part?.text)?.text;
}

export function buildAgentDocId(label: string, fileUri: string): string {
  try {
    const { object } = parseGsUri(fileUri);
    const clean = object.replace(/[^a-zA-Z0-9-_]/g, '_').slice(0, 40);
    return `${label}-${clean || 'doc'}`;
  } catch {
    return `${label}-${Date.now()}`;
  }
}

export function vlog(...args: any[]): void {
  if (LOG_GENAI_SUCCESS) console.log(...args);
}

export async function withTimeout<T>(
  promise: Promise<T>,
  ms: number,
  label: string,
): Promise<T> {
  let timeout: NodeJS.Timeout | undefined;
  const wrapped = new Promise<never>((_, reject) => {
    timeout = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
  });
  try {
    return await Promise.race([promise, wrapped]);
  } finally {
    if (timeout) clearTimeout(timeout);
  }
}

function vertexGenerateContentUrl(modelId: string): string {
  return `https://aiplatform.googleapis.com/v1/projects/${VERTEX_PROJECT}/locations/${IMAGE_REGION}/publishers/google/models/${modelId}:generateContent`;
}
