import { Storage } from '@google-cloud/storage';
import { parseGsUri } from '../utils.js';
import { enqueueAgentJob, waitForAgentJob } from './agent_queue.js';
import { buildAgentDocId, withTimeout } from './generation_shared.js';

type AgentFallbackParams = {
  label: string;
  prompt: string;
  fileUri: string;
  mimeType: string;
  modelId: string;
  docId?: string;
};

export type AgentJsonFallbackResult =
  | { handled: true; value: any }
  | { handled: false };

const storage = new Storage();
const GCS_READ_TIMEOUT_MS = Number(process.env.GCS_READ_TIMEOUT_MS ?? 30_000);

export async function queueImageAgentFallback(
  params: AgentFallbackParams,
): Promise<string | undefined> {
  const queued = await enqueueAgentJob(
    params.label,
    params.prompt,
    params.fileUri,
    params.mimeType,
    params.modelId,
    params.docId ?? buildAgentDocId(params.label, params.fileUri),
  );
  if (!queued) return undefined;

  const fromQueue = await waitForAgentJob(queued, params.label);
  if (fromQueue?.outputB64) return fromQueue.outputB64;
  if (!fromQueue?.outputPath) return undefined;

  const { bucket, object } = parseGsUri(fromQueue.outputPath);
  try {
    const [buf] = await withTimeout(
      storage.bucket(bucket).file(object).download(),
      GCS_READ_TIMEOUT_MS,
      `${params.label}-gcs-download`,
    );
    return Buffer.from(buf).toString('base64');
  } catch (err) {
    console.warn(`${params.label}: agent output download failed`, {
      error: String((err as any)?.message ?? err),
    });
    return undefined;
  }
}

export async function queueJsonAgentFallback(
  params: AgentFallbackParams,
): Promise<AgentJsonFallbackResult> {
  const queued = await enqueueAgentJob(
    params.label,
    params.prompt,
    params.fileUri,
    params.mimeType,
    params.modelId,
    params.docId ?? buildAgentDocId(params.label, params.fileUri),
  );
  if (!queued) return { handled: false };

  const res = await waitForAgentJob(queued, params.label);
  if (res?.outputText) {
    try {
      return { handled: true, value: JSON.parse(res.outputText) };
    } catch {
      return { handled: true, value: undefined };
    }
  }
  if (!res?.outputPath) return { handled: false };

  try {
    const { bucket, object } = parseGsUri(res.outputPath);
    const [buf] = await storage.bucket(bucket).file(object).download();
    const jsonText = Buffer.from(buf).toString('utf8');
    return { handled: true, value: JSON.parse(jsonText) };
  } catch {
    return { handled: true, value: undefined };
  }
}
