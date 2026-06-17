import type { Express, Request, Response } from 'express';
import bodyParser from 'body-parser';
import { Timestamp, type CollectionReference } from '@google-cloud/firestore';

type IngestPubSubSession = {
  status?: string;
  ingestion?: {
    job_ids?: string[];
  };
};

type RegisterIngestPubSubRoutesParams = {
  app: Express;
  sessions: CollectionReference;
  audit: (id: string, event: string, data?: unknown) => Promise<void>;
};

type PubSubDecodedMessage = {
  job_id?: string;
  jobId?: string;
  session_id?: string;
  status?: string;
};

type PubSubSkipReason =
  | 'invalid_json'
  | 'invalid_message'
  | 'session_id_not_found'
  | 'session_not_found'
  | 'status_required';

type PubSubDecodeResult =
  | { ok: true; value: PubSubDecodedMessage }
  | { ok: false; reason: PubSubSkipReason };

type PubSubSkipContext = {
  jobId?: string;
  message?: string;
  sessionId?: string;
  status?: string;
};

export function registerIngestPubSubRoutes(params: RegisterIngestPubSubRoutesParams): void {
  const pubsubRaw = bodyParser.raw({ type: '*/*' });

  params.app.all(['/ingest-pubsub', '/'], (req, res) => {
    if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');
    return pubsubRaw(req, res, (err) => {
      if (err) {
        console.error('ingest-pubsub parse error', err);
        return acknowledgeSkippedPubSubMessage(params, res, 'invalid_json', { message: err.message });
      }
      return handleIngestPubSub(params, req, res);
    });
  });
}

async function handleIngestPubSub(
  params: RegisterIngestPubSubRoutesParams,
  req: Request,
  res: Response,
): Promise<Response | void> {
  try {
    const decodedMessage = decodePubSubMessage((req as any).body);
    if (!decodedMessage.ok) {
      return acknowledgeSkippedPubSubMessage(params, res, decodedMessage.reason);
    }
    const decoded = decodedMessage.value;
    const jobId = decoded.job_id || decoded.jobId;
    const status = decoded.status;
    let sessionId = decoded.session_id;

    console.log('ingest-pubsub received', { jobId, status, sessionId });

    if (!status) {
      return acknowledgeSkippedPubSubMessage(params, res, 'status_required', { jobId, sessionId });
    }

    if (!sessionId && jobId) {
      const snap = await params.sessions.where('ingestion.job_ids', 'array-contains', jobId).limit(1).get();
      if (!snap.empty) sessionId = snap.docs[0].id;
    }
    if (!sessionId) {
      return acknowledgeSkippedPubSubMessage(params, res, 'session_id_not_found', { jobId, status });
    }

    const snap = await loadSession(params, sessionId);
    if (!snap) {
      return acknowledgeSkippedPubSubMessage(params, res, 'session_not_found', { jobId, sessionId, status });
    }

    const normalized = normalizeIngestStatus(status);
    const updates: any = {
      ingestion: {
        job_ids: snap.ingestion?.job_ids ?? (jobId ? [jobId] : []),
        status: normalized,
      },
      updated_at: Timestamp.now(),
    };
    if (normalized === 'succeeded' && snap.status === 'ingesting') {
      updates.status = 'ready';
    }

    await params.sessions.doc(sessionId).update(updates);
    await params.audit(sessionId, 'ingest_pubsub', buildPubSubAuditData({ jobId, status: normalized }));
    return res.status(204).send();
  } catch (err: any) {
    console.error('ingest-pubsub error', err);
    return res.status(500).json({ error: 'ingest_pubsub_failed', message: err.message });
  }
}

async function loadSession(
  params: RegisterIngestPubSubRoutesParams,
  sessionId: string,
): Promise<(IngestPubSubSession & { id: string }) | null> {
  const snap = await params.sessions.doc(sessionId).get();
  if (!snap.exists) return null;
  return { id: sessionId, ...(snap.data() as IngestPubSubSession) };
}

function decodePubSubMessage(bodyRaw: unknown): PubSubDecodeResult {
  const body = parsePubSubRequestBody(bodyRaw);
  const msg: any = body?.message;
  if (!msg?.data || typeof msg.data !== 'string') return { ok: false, reason: 'invalid_message' };
  try {
    return {
      ok: true,
      value: JSON.parse(Buffer.from(msg.data, 'base64').toString('utf8')) as PubSubDecodedMessage,
    };
  } catch {
    return { ok: false, reason: 'invalid_json' };
  }
}

function parsePubSubRequestBody(body: unknown): any {
  if (Buffer.isBuffer(body)) {
    try {
      return JSON.parse(body.toString('utf8'));
    } catch {
      return undefined;
    }
  }
  if (typeof body === 'string') {
    try {
      return JSON.parse(body);
    } catch {
      return undefined;
    }
  }
  return body;
}

async function acknowledgeSkippedPubSubMessage(
  params: RegisterIngestPubSubRoutesParams,
  res: Response,
  reason: PubSubSkipReason,
  context: PubSubSkipContext = {},
): Promise<Response> {
  console.warn('Skipping ingest Pub/Sub push message', { reason, ...context });
  if (context.sessionId) {
    try {
      await params.audit(context.sessionId, 'ingest_pubsub_skipped', buildPubSubAuditData({
        reason,
        jobId: context.jobId,
        status: context.status,
      }));
    } catch (err) {
      console.warn('Failed to audit skipped ingest Pub/Sub message', { reason, sessionId: context.sessionId }, err);
    }
  }
  return res.status(204).send();
}

function buildPubSubAuditData(params: { reason?: string; jobId?: string; status?: string }): Record<string, string> {
  const data: Record<string, string> = {};
  if (params.reason) data.reason = params.reason;
  if (params.jobId) data.job_id = params.jobId;
  if (params.status) data.status = params.status;
  return data;
}

function normalizeIngestStatus(status: string): string {
  if (status === 'completed' || status === 'succeeded') return 'succeeded';
  if (status === 'partial_ok') return 'partial_ok';
  if (status === 'error' || status === 'failed') return 'error';
  return status;
}
