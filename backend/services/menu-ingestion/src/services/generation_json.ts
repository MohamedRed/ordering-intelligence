import { GEN_TIMEOUT_MS } from '../config.js';
import { queueJsonAgentFallback } from './generation_agent_outputs.js';
import {
  buildAgentDocId,
  extractGeminiText,
  fetchVertexContent,
  vlog,
} from './generation_shared.js';

export async function geminiJson(
  prompt: string,
  fileUri: string,
  mimeType: string,
  modelId: string,
  label = 'analysis-json',
): Promise<any> {
  const body = buildJsonBody(prompt, [{ fileData: { fileUri, mimeType } }]);
  let resText = '';
  const start = Date.now();
  try {
    const response = await fetchVertexContent({ modelId, body, timeoutMs: GEN_TIMEOUT_MS });
    resText = response.resText;
    assertJsonResponse(label, 'analysis-json', response.res, resText, response.contentType);
  } catch (err) {
    console.error(`${label} error`, err);
    const fallback = await queueJsonAgentFallback({
      label,
      prompt,
      fileUri,
      mimeType,
      modelId,
      docId: buildAgentDocId(label, fileUri),
    });
    if (fallback.handled) return fallback.value;
    throw err;
  }

  const parsed = parseVertexResponse('analysis-json', resText);
  const text = extractGeminiText(parsed);
  if (!text) {
    console.warn('gemini json missing text', { model: modelId, raw: parsed });
    return undefined;
  }
  try {
    const json = JSON.parse(text);
    vlog('genai json success', { label, modelId, ms: Date.now() - start });
    return json;
  } catch (err) {
    console.error('gemini json parse error', err);
    return undefined;
  }
}

export async function geminiJsonText(
  prompt: string,
  modelId: string,
  label = 'analysis-json-text',
): Promise<any> {
  const body = buildJsonBody(prompt);
  let resText = '';
  const start = Date.now();
  try {
    const response = await fetchVertexContent({ modelId, body, timeoutMs: GEN_TIMEOUT_MS });
    resText = response.resText;
    assertJsonResponse(label, 'analysis-json-text', response.res, resText, response.contentType);
  } catch (err) {
    console.error(`${label} error`, err);
    throw err;
  }

  const parsed = parseVertexResponse('analysis-json-text', resText);
  const text = extractGeminiText(parsed);
  if (!text) {
    console.warn('gemini json text missing text', { model: modelId, raw: parsed });
    return undefined;
  }
  try {
    const json = JSON.parse(text);
    vlog('genai json text success', { label, modelId, ms: Date.now() - start });
    return json;
  } catch (err) {
    console.error('gemini json text parse error', err);
    return undefined;
  }
}

function buildJsonBody(
  prompt: string,
  extraParts: Array<Record<string, unknown>> = [],
): Record<string, unknown> {
  return {
    contents: [
      {
        role: 'user',
        parts: [{ text: prompt }, ...extraParts],
      },
    ],
    generationConfig: {
      responseMimeType: 'application/json',
      temperature: 0.1,
    },
  };
}

function assertJsonResponse(
  label: string,
  logLabel: string,
  res: any,
  resText: string,
  contentType: string,
): void {
  if (res.ok && contentType.includes('application/json')) return;
  console.error(`${logLabel} fetch failed`, {
    status: res.status,
    statusText: res.statusText,
    bodySnippet: resText.slice(0, 400),
    contentType,
  });
  throw Object.assign(new Error(`${label} failed status ${res.status}`), { status: res.status });
}

function parseVertexResponse(logLabel: string, resText: string): any {
  try {
    return JSON.parse(resText);
  } catch (err) {
    console.error(`${logLabel} response parse error`, {
      message: (err as Error).message,
      resText: resText.slice(0, 200),
    });
    return undefined;
  }
}
