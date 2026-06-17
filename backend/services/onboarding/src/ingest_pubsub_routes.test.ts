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
      get: async () => ({
        exists: params.session !== null,
        data: () => ({
          status: 'ingesting',
          ingestion: { job_ids: ['job-existing'] },
          ...(params.session ?? {}),
        }),
      }),
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

  it('acknowledges malformed Pub/Sub payloads before decoding', async () => {
    const { app, audits, updates } = makeHarness();

    await request(app).post('/ingest-pubsub').send({ message: {} }).expect(204);

    expect(audits).toEqual([]);
    expect(updates).toEqual([]);
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

  it('updates an explicit session without writing undefined audit fields when job id is omitted', async () => {
    const { app, audits, updates } = makeHarness();

    await request(app)
      .post('/ingest-pubsub')
      .send(pubsubPayload({ session_id: 'session-1', status: 'partial_ok' }))
      .expect(204);

    expect(updates[0]).toMatchObject({
      id: 'session-1',
      payload: {
        ingestion: { job_ids: ['job-existing'], status: 'partial_ok' },
      },
    });
    expect(audits).toEqual([
      {
        id: 'session-1',
        event: 'ingest_pubsub',
        data: { status: 'partial_ok' },
      },
    ]);
  });

  it('acknowledges messages without status and audits the skipped session event', async () => {
    const { app, audits, updates } = makeHarness();

    await request(app)
      .post('/ingest-pubsub')
      .send(pubsubPayload({ session_id: 'session-1', job_id: 'job-1' }))
      .expect(204);

    expect(updates).toEqual([]);
    expect(audits).toEqual([
      {
        id: 'session-1',
        event: 'ingest_pubsub_skipped',
        data: { reason: 'status_required', job_id: 'job-1' },
      },
    ]);
  });

  it('acknowledges messages without a resolvable session id', async () => {
    const { app, audits, updates, whereCalls } = makeHarness();

    await request(app)
      .post('/ingest-pubsub')
      .send(pubsubPayload({ job_id: 'job-1', status: 'processing' }))
      .expect(204);

    expect(whereCalls).toEqual([{ field: 'ingestion.job_ids', op: 'array-contains', value: 'job-1' }]);
    expect(updates).toEqual([]);
    expect(audits).toEqual([]);
  });

  it('acknowledges stale messages for deleted sessions', async () => {
    const { app, audits, updates } = makeHarness({ session: null });

    await request(app)
      .post('/ingest-pubsub')
      .send(pubsubPayload({ session_id: 'deleted-session', job_id: 'job-1', status: 'completed' }))
      .expect(204);

    expect(updates).toEqual([]);
    expect(audits).toHaveLength(1);
    expect(audits[0]).toMatchObject({
      id: 'deleted-session',
      event: 'ingest_pubsub_skipped',
      data: { reason: 'session_not_found', job_id: 'job-1', status: 'completed' },
    });
  });
});
