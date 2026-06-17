import type { Express, Response } from 'express';
import { Timestamp, type CollectionReference, type Firestore } from '@google-cloud/firestore';

type SessionStatusView = {
  status?: string;
  ingestion?: {
    job_ids?: string[];
    status?: string;
    fast_ready?: boolean;
  };
  stripe?: unknown;
  twilio?: unknown;
  agent?: unknown;
  audit?: unknown[];
};

type RegisterSessionStatusRoutesParams = {
  app: Express;
  firestore: Firestore;
  sessions: CollectionReference;
  getSession: (id: string, res: Response) => Promise<(SessionStatusView & { id: string }) | null>;
  audit: (id: string, event: string, data?: unknown) => Promise<void>;
};

type IngestSyncState = {
  status: string;
  fastReady: boolean;
  bestPercent: number;
  bestStage: string;
};

export function registerSessionStatusRoutes(params: RegisterSessionStatusRoutesParams): void {
  params.app.get('/onboarding-sessions/:id/status', async (req, res) => {
    const snap = await params.getSession(req.params.id, res);
    if (!snap) return;
    return res.json({
      status: snap.status,
      ingestion: snap.ingestion,
      stripe: snap.stripe,
      twilio: snap.twilio,
      agent: snap.agent,
    });
  });

  params.app.get('/onboarding-sessions/:id/audit', async (req, res) => {
    const snap = await params.getSession(req.params.id, res);
    if (!snap) return;
    return res.json({ audit: snap.audit ?? [] });
  });

  params.app.post('/onboarding-sessions/:id/sync-ingest', async (req, res) => {
    try {
      const { id } = req.params;
      const snap = await params.getSession(id, res);
      if (!snap) return;

      const jobIds = snap.ingestion?.job_ids || [];
      if (!jobIds.length) {
        return res.json({ status: 'not_started', progress: { percent: 0, stage: 'not_started' } });
      }

      const jobsSnap = await params.firestore.getAll(
        ...jobIds.map((jid) => params.firestore.collection('menus_ingest').doc(jid)),
      );
      const syncState = resolveIngestSyncState(jobsSnap, {
        status: snap.ingestion?.status || 'unknown',
        fastReady: !!snap.ingestion?.fast_ready,
        bestPercent: 0,
        bestStage: '',
      });

      await params.sessions.doc(id).update({
        ingestion: { job_ids: jobIds, status: syncState.status, fast_ready: syncState.fastReady },
        updated_at: Timestamp.now(),
      });
      await params.audit(id, 'ingest_synced', {
        status: syncState.status,
        fast_ready: syncState.fastReady,
      });
      return res.json({
        status: syncState.status,
        fast_ready: syncState.fastReady,
        progress: { percent: syncState.bestPercent, stage: syncState.bestStage },
      });
    } catch (err: any) {
      console.error('sync-ingest error', err);
      return res.status(500).json({ error: 'sync_ingest_failed', message: err.message });
    }
  });

  params.app.get('/onboarding-sessions/:id/ingest-workflow', async (req, res) => {
    try {
      const { id } = req.params;
      const snap = await params.getSession(id, res);
      if (!snap) return;

      const jobIds = snap.ingestion?.job_ids || [];
      if (!jobIds.length) return res.json({ job_id: null, nodes: [] });

      const requested = (req.query.job_id as string | undefined)?.trim();
      const jobId = (requested && jobIds.includes(requested) ? requested : jobIds[0]) as string;
      const limitRaw = Number(req.query.limit ?? 600);
      const limit = Number.isFinite(limitRaw) ? Math.max(1, Math.min(2000, limitRaw)) : 600;

      const nodesSnap = await params.firestore
        .collection('menus_ingest')
        .doc(jobId)
        .collection('workflow_nodes')
        .limit(limit)
        .get();
      const nodes = nodesSnap.docs.map((doc) => doc.data()).sort(compareWorkflowNodes);
      return res.json({ job_id: jobId, nodes });
    } catch (err: any) {
      console.error('ingest-workflow error', err);
      return res.status(500).json({ error: 'ingest_workflow_failed', message: err.message });
    }
  });
}

function resolveIngestSyncState(jobsSnap: Array<{ exists: boolean; data: () => any }>, initial: IngestSyncState): IngestSyncState {
  const state = { ...initial };
  for (const jobSnap of jobsSnap) {
    if (!jobSnap.exists) continue;
    const data = jobSnap.data() as any;
    const pct = typeof data.progressPercent === 'number' ? data.progressPercent : undefined;
    const stage = typeof data.progressStage === 'string' ? data.progressStage : undefined;
    const readyKind = typeof data.readyKind === 'string' ? data.readyKind : undefined;

    if (readyKind && ['menu_only', 'full'].includes(readyKind.toLowerCase())) state.fastReady = true;
    if (pct != null && pct >= state.bestPercent) {
      state.bestPercent = pct;
      state.bestStage = stage || '';
    }

    if (data.status === 'canceled') {
      state.status = 'canceled';
      break;
    }
    if (data.status === 'error') {
      state.status = 'error';
      break;
    }
    if (data.status === 'processing') state.status = 'processing';
    if (data.status === 'queued' && state.status !== 'processing') state.status = 'queued';
    if (data.status === 'uploading' && state.status !== 'processing') state.status = 'queued';
    if (data.status === 'ready') state.status = 'succeeded';
    if (data.status === 'completed' || data.status === 'succeeded') state.status = 'succeeded';
    if (data.status === 'ready' || data.status === 'completed' || data.status === 'succeeded') {
      state.fastReady = true;
    }
  }

  if (!state.bestStage) state.bestStage = stageForStatus(state.status);
  if (state.status === 'succeeded') state.bestPercent = 100;
  if (state.status === 'error' && state.bestPercent < 100) state.bestPercent = 100;
  if (state.status === 'canceled' && state.bestPercent < 100) state.bestPercent = 100;
  return state;
}

function stageForStatus(status: string): string {
  if (status === 'succeeded') return 'done';
  if (status === 'processing') return 'processing';
  if (status === 'queued') return 'queued';
  if (status === 'canceled') return 'canceled';
  if (status === 'error') return 'error';
  return status;
}

function compareWorkflowNodes(a: any, b: any): number {
  const seqA = typeof a.seq === 'number' ? a.seq : Number.MAX_SAFE_INTEGER;
  const seqB = typeof b.seq === 'number' ? b.seq : Number.MAX_SAFE_INTEGER;
  if (seqA !== seqB) return seqA - seqB;
  const startedA = typeof a.startedAt === 'number' ? a.startedAt : 0;
  const startedB = typeof b.startedAt === 'number' ? b.startedAt : 0;
  return startedA - startedB;
}
