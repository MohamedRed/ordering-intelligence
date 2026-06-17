import express from 'express';
import request from 'supertest';
import { registerAgentCreationRoutes } from './agent_creation_routes';

function makeFirestore(params: { ingestJob?: any; draftExists?: boolean } = {}) {
  const reads: Array<{ collection: string; id: string }> = [];
  return {
    reads,
    firestore: {
      collection: (name: string) => ({
        doc: (id: string) => ({
          get: async () => {
            reads.push({ collection: name, id });
            if (name === 'menus_ingest') {
              return {
                exists: params.ingestJob !== undefined,
                data: () => params.ingestJob,
              };
            }
            if (name === 'menus_drafts') {
              return {
                exists: params.draftExists ?? false,
                data: () => ({}),
              };
            }
            return { exists: false, data: () => undefined };
          },
        }),
      }),
    },
  };
}

function makeHarness(params: {
  session?: any;
  ingestJob?: any;
  draftExists?: boolean;
  resolveTemplateAgentId?: jest.Mock;
} = {}) {
  const app = express();
  app.use(express.json());

  const { firestore, reads } = makeFirestore({
    ingestJob: params.ingestJob,
    draftExists: params.draftExists,
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
  const resolveTemplateAgentId = params.resolveTemplateAgentId ?? jest.fn(() => 'template-fast');

  registerAgentCreationRoutes({
    app,
    firestore: firestore as any,
    sessions: sessions as any,
    resolveTemplateAgentId,
    getSession: async (id, res) => {
      if (params.session === null) {
        res.status(404).json({ error: 'session_not_found' });
        return null;
      }
      return {
        id,
        ingestion: { status: 'succeeded', job_ids: ['job-1'] },
        business: { type: 'fast_food' },
        ...(params.session ?? {}),
      };
    },
    audit: async (id, event, data) => {
      audits.push({ id, event, data });
    },
  });

  return { app, audits, reads, resolveTemplateAgentId, updates };
}

describe('agent creation onboarding route', () => {
  it('returns existing shared-template agent configuration idempotently', async () => {
    const { app, reads, updates } = makeHarness({
      session: { agent: { template_agent_id: 'template-existing' } },
    });

    const res = await request(app).post('/onboarding-sessions/session-1/create-agent').send({}).expect(200);

    expect(res.body).toEqual({
      reused: true,
      agent_mode: 'shared_template',
      template_agent_id: 'template-existing',
      agent_id: 'template-existing',
    });
    expect(reads).toEqual([]);
    expect(updates).toEqual([]);
  });

  it('returns existing per-tenant agent configuration idempotently', async () => {
    const { app } = makeHarness({
      session: { agent: { agent_id: 'agent-existing' } },
    });

    const res = await request(app).post('/onboarding-sessions/session-1/create-agent').send({}).expect(200);

    expect(res.body).toEqual({
      reused: true,
      agent_mode: 'per_tenant',
      template_agent_id: null,
      agent_id: 'agent-existing',
    });
  });

  it('rejects agent creation until ingestion is ready', async () => {
    const { app, audits, updates } = makeHarness({
      session: { ingestion: { status: 'processing', job_ids: [] } },
    });

    const res = await request(app).post('/onboarding-sessions/session-1/create-agent').send({}).expect(400);

    expect(res.body).toEqual({ error: 'ingestion_not_ready', status: 'processing' });
    expect(updates).toEqual([]);
    expect(audits).toEqual([]);
  });

  it('uses a ready ingest job as the creation gate when session status is still processing', async () => {
    const { app, audits, reads, resolveTemplateAgentId, updates } = makeHarness({
      session: { ingestion: { status: 'processing', job_ids: ['job-1'] }, business: { type: 'AUTO_PARTS' } },
      ingestJob: { readyKind: 'menu_only' },
    });

    const res = await request(app).post('/onboarding-sessions/session-1/create-agent').send({}).expect(200);

    expect(res.body).toEqual({
      reused: false,
      agent_mode: 'shared_template',
      template_agent_id: 'template-fast',
      agent_id: 'template-fast',
    });
    expect(reads).toEqual([{ collection: 'menus_ingest', id: 'job-1' }]);
    expect(resolveTemplateAgentId).toHaveBeenCalledWith('auto_parts');
    expect(updates[0].payload.agent).toEqual({
      mode: 'shared_template',
      template_agent_id: 'template-fast',
      business_type: 'auto_parts',
      status: 'configured',
    });
    expect(audits).toEqual([
      {
        id: 'session-1',
        event: 'agent_created',
        data: {
          template_agent_id: 'template-fast',
          business_type: 'auto_parts',
          mode: 'shared_template',
        },
      },
    ]);
  });

  it('uses an existing menu draft as a readiness signal', async () => {
    const { app, reads } = makeHarness({
      session: { ingestion: { status: 'queued', job_ids: ['job-2'] } },
      draftExists: true,
    });

    await request(app).post('/onboarding-sessions/session-1/create-agent').send({}).expect(200);

    expect(reads).toEqual([
      { collection: 'menus_ingest', id: 'job-2' },
      { collection: 'menus_drafts', id: 'job-2' },
    ]);
  });

  it('returns a configuration error when no template is available for the business type', async () => {
    const resolveTemplateAgentId = jest.fn(() => '');
    const { app, audits, updates } = makeHarness({
      resolveTemplateAgentId,
      session: { business: { type: 'gas_station' } },
    });

    const res = await request(app).post('/onboarding-sessions/session-1/create-agent').send({}).expect(500);

    expect(res.body).toEqual({
      error: 'elevenlabs_template_not_configured',
      business_type: 'gas_station',
    });
    expect(resolveTemplateAgentId).toHaveBeenCalledWith('gas_station');
    expect(updates).toEqual([]);
    expect(audits).toEqual([]);
  });
});
