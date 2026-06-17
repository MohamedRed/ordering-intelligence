import express from 'express';
import request from 'supertest';
import { registerIngestPubSubRoutes } from './ingest_pubsub_routes';

function pubsubPayload(decoded: Record<string, unknown>) {
  return {
    message: {
      data: Buffer.from(JSON.stringify(decoded), 'utf8').toString('base64'),
    },
  };
}

function makeHarness(params: {
  session?: any;
  lookupSessionId?: string;
} = {}) {
  const app = express();
  const updates: Array<{ id: string; payload: any }> = [];
  const audits: Array<{ id: string; event: string; data?: unknown }> = [];
  const whereCalls: Array<{ field: string; op: string; value: unknown }> = [];

  const sessions = {
    doc: (id: string) => ({
      update: async (payload: any) => {
        updates.push({ id, payload });
      },
    }),
    where: (field: string, op: string, value: unknown) => {
      whereCalls.push({ field, op, value });
      return {
        limit: () => ({
          get: async () => ({
            empty: !params.lookupSessionId,
            docs: params.lookupSessionId ? [{ id: params.lookupSessionId }] : [],
          }),
        }),
      };
    },
  };

  registerIngestPubSubRoutes({
    app,
    sessions: sessions as any,
    getSession: async (id, res) => {
      if (params.session === null) {
        res.status(404).json({ error: 'session_not_found' });
        return null;
      }
      return {
        id,
        status: 'ingesting',
        ingestion: { job_ids: ['job-existing'] },
        ...(params.session ?? {}),
      };
    },
    audit: async (id, event, data) => {
      audits.push({ id, event, data });
    },
  });

  return { app, audits, updates, whereCalls };
}

describe('ingest Pub/Sub routes', () => {
  it('rejects non-POST requests on the push endpoint', async () => {
    const { app } = makeHarness();

    await request(app).get('/ingest-pubsub').expect(405, 'Method Not Allowed');
  });

  it('rejects malformed Pub/Sub payloads before decoding', async () => {
    const { app } = makeHarness();

    const res = await request(app).post('/ingest-pubsub').send({ message: {} }).expect(400);

    expect(res.body.error).toBe('invalid_message');
  });

  it('updates the explicit onboarding session and normalizes completed status', async () => {
    const { app, audits, updates, whereCalls } = makeHarness();

    await request(app)
      .post('/ingest-pubsub')
      .send(pubsubPayload({ session_id: 'session-1', job_id: 'job-1', status: 'completed' }))
      .expect(204);

    expect(whereCalls).toEqual([]);
    expect(updates[0]).toMatchObject({
      id: 'session-1',
      payload: {
        ingestion: { job_ids: ['job-existing'], status: 'succeeded' },
        status: 'ready',
      },
    });
    expect(audits).toEqual([
      {
        id: 'session-1',
        event: 'ingest_pubsub',
        data: { job_id: 'job-1', status: 'succeeded' },
      },
    ]);
  });

  it('looks up the onboarding session from the ingest job id when session id is omitted', async () => {
    const { app, audits, updates, whereCalls } = makeHarness({
      lookupSessionId: 'session-from-job',
      session: { status: 'collecting', ingestion: {} },
    });

    await request(app)
      .post('/ingest-pubsub')
      .send(pubsubPayload({ jobId: 'job-lookup', status: 'failed' }))
      .expect(204);

    expect(whereCalls).toEqual([
      { field: 'ingestion.job_ids', op: 'array-contains', value: 'job-lookup' },
    ]);
    expect(updates[0]).toMatchObject({
      id: 'session-from-job',
      payload: {
        ingestion: { job_ids: ['job-lookup'], status: 'error' },
      },
    });
    expect(updates[0].payload.status).toBeUndefined();
    expect(audits[0]).toMatchObject({
      id: 'session-from-job',
      event: 'ingest_pubsub',
      data: { job_id: 'job-lookup', status: 'error' },
    });
  });

  it('requires a status and a resolvable session id', async () => {
    const { app } = makeHarness();

    const missingStatus = await request(app)
      .post('/ingest-pubsub')
      .send(pubsubPayload({ session_id: 'session-1', job_id: 'job-1' }))
      .expect(400);
    expect(missingStatus.body.error).toBe('status_required');

    const missingSession = await request(app)
      .post('/ingest-pubsub')
      .send(pubsubPayload({ job_id: 'job-1', status: 'processing' }))
      .expect(400);
    expect(missingSession.body.error).toBe('session_id_not_found');
  });
});
