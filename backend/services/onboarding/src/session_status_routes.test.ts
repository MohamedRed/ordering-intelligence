import express from 'express';
import request from 'supertest';
import { registerSessionStatusRoutes } from './session_status_routes';

function makeFirestore(params: {
  ingestJobs?: Record<string, any>;
  workflowNodes?: Record<string, any[]>;
} = {}) {
  const limits: Array<{ jobId: string; limit: number }> = [];
  const refs: Array<{ collection: string; id: string }> = [];
  const firestore = {
    collection: (name: string) => ({
      doc: (id: string) => {
        refs.push({ collection: name, id });
        return {
          id,
          collection: (subcollection: string) => ({
            limit: (limit: number) => ({
              get: async () => {
                limits.push({ jobId: id, limit });
                const nodes = subcollection === 'workflow_nodes' ? params.workflowNodes?.[id] ?? [] : [];
                return { docs: nodes.map((node) => ({ data: () => node })) };
              },
            }),
          }),
        };
      },
    }),
    getAll: async (...documents: Array<{ id: string }>) =>
      documents.map((doc) => {
        const data = params.ingestJobs?.[doc.id];
        return {
          exists: data !== undefined,
          data: () => data,
        };
      }),
  };
  return { firestore, limits, refs };
}

function makeHarness(params: {
  session?: any;
  ingestJobs?: Record<string, any>;
  workflowNodes?: Record<string, any[]>;
} = {}) {
  const app = express();
  app.use(express.json());

  const { firestore, limits, refs } = makeFirestore({
    ingestJobs: params.ingestJobs,
    workflowNodes: params.workflowNodes,
  });
  const updates: Array<{ id: string; payload: any }> = [];
  const audits: Array<{ id: string; event: string; data?: unknown }> = [];
  const sessions = {
    doc: (id: string) => ({
      update: async (payload: any) => {
        updates.push({ id, payload });
      },
    }),
  };

  registerSessionStatusRoutes({
    app,
    firestore: firestore as any,
    sessions: sessions as any,
    getSession: async (id, res) => {
      if (params.session === null) {
        res.status(404).json({ error: 'session_not_found' });
        return null;
      }
      return {
        id,
        status: 'ingesting',
        ingestion: { status: 'queued', job_ids: ['job-1'], fast_ready: false },
        stripe: { status: 'pending' },
        twilio: { number: '+15551230000' },
        agent: { template_agent_id: 'template-fast' },
        audit: [{ event: 'created' }],
        ...(params.session ?? {}),
      };
    },
    audit: async (id, event, data) => {
      audits.push({ id, event, data });
    },
  });

  return { app, audits, limits, refs, updates };
}

describe('session status onboarding routes', () => {
  it('returns compact status and audit views', async () => {
    const { app } = makeHarness();

    const statusRes = await request(app).get('/onboarding-sessions/session-1/status').expect(200);
    const auditRes = await request(app).get('/onboarding-sessions/session-1/audit').expect(200);

    expect(statusRes.body).toEqual({
      status: 'ingesting',
      ingestion: { status: 'queued', job_ids: ['job-1'], fast_ready: false },
      stripe: { status: 'pending' },
      twilio: { number: '+15551230000' },
      agent: { template_agent_id: 'template-fast' },
    });
    expect(auditRes.body).toEqual({ audit: [{ event: 'created' }] });
  });

  it('reports ingestion as not started when no jobs are attached', async () => {
    const { app, audits, updates } = makeHarness({
      session: { ingestion: { job_ids: [] } },
    });

    const res = await request(app).post('/onboarding-sessions/session-1/sync-ingest').send({}).expect(200);

    expect(res.body).toEqual({
      status: 'not_started',
      progress: { percent: 0, stage: 'not_started' },
    });
    expect(updates).toEqual([]);
    expect(audits).toEqual([]);
  });

  it('syncs ingestion state from menu ingest jobs and audits the normalized result', async () => {
    const { app, audits, updates } = makeHarness({
      session: { ingestion: { status: 'queued', job_ids: ['job-1', 'job-2'], fast_ready: false } },
      ingestJobs: {
        'job-1': { status: 'processing', progressPercent: 35, progressStage: 'vision' },
        'job-2': { status: 'ready', readyKind: 'menu_only', progressPercent: 75, progressStage: 'draft' },
      },
    });

    const res = await request(app).post('/onboarding-sessions/session-1/sync-ingest').send({}).expect(200);

    expect(res.body).toEqual({
      status: 'succeeded',
      fast_ready: true,
      progress: { percent: 100, stage: 'draft' },
    });
    expect(updates[0].payload.ingestion).toEqual({
      job_ids: ['job-1', 'job-2'],
      status: 'succeeded',
      fast_ready: true,
    });
    expect(audits).toEqual([
      {
        id: 'session-1',
        event: 'ingest_synced',
        data: { status: 'succeeded', fast_ready: true },
      },
    ]);
  });

  it('syncs canceled ingestion as a terminal state with completed progress', async () => {
    const { app, updates } = makeHarness({
      session: { ingestion: { status: 'queued', job_ids: ['job-canceled'], fast_ready: false } },
      ingestJobs: {
        'job-canceled': { status: 'canceled' },
      },
    });

    const res = await request(app).post('/onboarding-sessions/session-1/sync-ingest').send({}).expect(200);

    expect(res.body).toEqual({
      status: 'canceled',
      fast_ready: false,
      progress: { percent: 100, stage: 'canceled' },
    });
    expect(updates[0].payload.ingestion).toEqual({
      job_ids: ['job-canceled'],
      status: 'canceled',
      fast_ready: false,
    });
  });

  it('returns an empty workflow when no ingestion jobs are attached', async () => {
    const { app, limits } = makeHarness({
      session: { ingestion: { job_ids: [] } },
    });

    const res = await request(app).get('/onboarding-sessions/session-1/ingest-workflow').expect(200);

    expect(res.body).toEqual({ job_id: null, nodes: [] });
    expect(limits).toEqual([]);
  });

  it('sorts workflow nodes and clamps the requested limit', async () => {
    const { app, limits } = makeHarness({
      session: { ingestion: { job_ids: ['job-1', 'job-2'] } },
      workflowNodes: {
        'job-2': [
          { id: 'last', seq: 2, startedAt: 20 },
          { id: 'first', seq: 1, startedAt: 30 },
          { id: 'second', seq: 1, startedAt: 40 },
        ],
      },
    });

    const res = await request(app)
      .get('/onboarding-sessions/session-1/ingest-workflow?job_id=job-2&limit=5000')
      .expect(200);

    expect(res.body).toEqual({
      job_id: 'job-2',
      nodes: [
        { id: 'first', seq: 1, startedAt: 30 },
        { id: 'second', seq: 1, startedAt: 40 },
        { id: 'last', seq: 2, startedAt: 20 },
      ],
    });
    expect(limits).toEqual([{ jobId: 'job-2', limit: 2000 }]);
  });

  it('falls back to the first session job when a requested workflow job is not attached', async () => {
    const { app, limits } = makeHarness({
      session: { ingestion: { job_ids: ['job-1'] } },
      workflowNodes: { 'job-1': [{ id: 'only' }] },
    });

    const res = await request(app)
      .get('/onboarding-sessions/session-1/ingest-workflow?job_id=job-other&limit=bad')
      .expect(200);

    expect(res.body).toEqual({ job_id: 'job-1', nodes: [{ id: 'only' }] });
    expect(limits).toEqual([{ jobId: 'job-1', limit: 600 }]);
  });
});
