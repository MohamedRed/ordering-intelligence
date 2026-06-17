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
  getSession: (id: string, res: Response) => Promise<(IngestPubSubSession & { id: string }) | null>;
  audit: (id: string, event: string, data?: unknown) => Promise<void>;
};

type PubSubDecodedMessage = {
  job_id?: string;
  jobId?: string;
  session_id?: string;
  status?: string;
};

export function registerIngestPubSubRoutes(params: RegisterIngestPubSubRoutesParams): void {
  const pubsubRaw = bodyParser.raw({ type: '*/*' });

  params.app.all(['/ingest-pubsub', '/'], (req, res) => {
    if (req.method !== 'POST') return res.status(405).send('Method Not Allowed');
    return pubsubRaw(req, res, (err) => {
      if (err) {
        console.error('ingest-pubsub parse error', err);
        return res.status(400).json({ error: 'invalid_json', message: err.message });
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
    const body = parsePubSubRequestBody((req as any).body);
    const msg: any = body?.message;
    if (!msg?.data) return res.status(400).json({ error: 'invalid_message' });

    const decoded = JSON.parse(Buffer.from(msg.data, 'base64').toString('utf8')) as PubSubDecodedMessage;
    const jobId = decoded.job_id || decoded.jobId;
    const status = decoded.status;
    let sessionId = decoded.session_id;

    console.log('ingest-pubsub received', { jobId, status, sessionId });

    if (!status) return res.status(400).json({ error: 'status_required' });

    if (!sessionId && jobId) {
      const snap = await params.sessions.where('ingestion.job_ids', 'array-contains', jobId).limit(1).get();
      if (!snap.empty) sessionId = snap.docs[0].id;
    }
    if (!sessionId) return res.status(400).json({ error: 'session_id_not_found' });

    const snap = await params.getSession(sessionId, res);
    if (!snap) return;

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
    await params.audit(sessionId, 'ingest_pubsub', { job_id: jobId, status: normalized });
    return res.status(204).send();
  } catch (err: any) {
    console.error('ingest-pubsub error', err);
    return res.status(500).json({ error: 'ingest_pubsub_failed', message: err.message });
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

function normalizeIngestStatus(status: string): string {
  if (status === 'completed' || status === 'succeeded') return 'succeeded';
  if (status === 'partial_ok') return 'partial_ok';
  if (status === 'error' || status === 'failed') return 'error';
  return status;
}
