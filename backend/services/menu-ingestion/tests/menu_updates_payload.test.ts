import express from 'express';
import supertest from 'supertest';
import { ingestRouter } from '../src/routes/ingest';
import { testRouter } from '../src/routes/test';

function makeHarness() {
  const publishMessage = jest.fn(async () => undefined);
  const batchWrites: any[] = [];
  const draft = {
    jobId: 'job-1',
    restaurantId: 'store-1',
    items: [{ id: 'item-1', name: 'Burger', priceCents: 1200, available: true }],
    bundleRules: [],
    updatedAt: 123,
  };

  const firestore = {
    batch: () => ({
      set: (ref: any, payload: any, options?: any) => batchWrites.push({ type: 'set', ref, payload, options }),
      update: (ref: any, payload: any) => batchWrites.push({ type: 'update', ref, payload }),
      commit: async () => undefined,
    }),
    collection: (name: string) => ({
      doc: (id: string) => ({
        collection: (childName: string) => ({
          doc: (childId: string) => ({ path: `${name}/${id}/${childName}/${childId}` }),
        }),
        get: async () => ({
          exists: name === 'menus_drafts',
          data: () => (name === 'menus_drafts' ? draft : undefined),
        }),
        path: `${name}/${id}`,
        set: async () => undefined,
      }),
    }),
  };

  const app = express();
  app.use(express.json());
  const ctx: any = {
    firestore,
    storage: {},
    pubsub: { topic: () => ({ publishMessage }) },
    bucket: 'menus-bucket',
    topic: 'menu-ingest',
    menuUpdatesTopic: 'menu-updates',
    signedReadUrls: async () => [],
    requireAuth: (_req: any, _res: any, next: any) => next(),
  };
  app.use(ingestRouter(ctx));
  app.use(testRouter(ctx));
  return { app, batchWrites, publishMessage };
}

describe('menu update Pub/Sub payloads', () => {
  it('includes a completed status when approving an ingested menu', async () => {
    const { app, publishMessage } = makeHarness();

    await supertest(app).post('/ingest/job-1/approve').send({}).expect(200);

    expect(publishMessage).toHaveBeenCalledWith({
      json: expect.objectContaining({
        jobId: 'job-1',
        source: 'menu-ingestion',
        status: 'completed',
        storeId: 'store-1',
      }),
    });
  });

  it('includes a completed status in the internal smoke-test menu update', async () => {
    const { app, publishMessage } = makeHarness();

    await supertest(app)
      .post('/internal/test/menu-update')
      .send({ storeId: 'store-1', jobId: 'job-2' })
      .expect(200);

    expect(publishMessage).toHaveBeenCalledWith({
      json: expect.objectContaining({
        jobId: 'job-2',
        source: 'internal_test',
        status: 'completed',
        storeId: 'store-1',
      }),
    });
  });
});
