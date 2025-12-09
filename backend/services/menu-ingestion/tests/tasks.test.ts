import { jest } from '@jest/globals';
import express, { type Express } from 'express';
import supertest from 'supertest';
// Keep processJob lightweight by mocking expensive steps.
jest.unstable_mockModule('../src/services/ingestion.js', () => ({
  analyzeMenuFromOriginal: async () => [],
  generateComposites: async () => ({ generatedFiles: [] }),
  extractItemsFromComposites: async () => ({ images: [], count: 0 }),
  assignThumbsToMenu: async () => [{ name: 'mock', price: 0 }],
}));

jest.unstable_mockModule('../src/services/generation.js', () => ({
  textModel: () => ({ generateContent: async () => ({}) }),
  imageModel: () => ({ generateContent: async () => ({}) }),
  throttledImageCall: async () => ({}),
}));

jest.unstable_mockModule('@google-cloud/vertexai', () => ({
  VertexAI: class VertexAI {
    constructor() {}
    getGenerativeModel() {
      return { generateContent: async () => ({}) };
    }
  },
}));

process.env.GOOGLE_CLOUD_PROJECT = 'test-project';
process.env.VERTEX_PROJECT = 'test-project';
process.env.IMAGE_REGION = 'us-central1';

type Job = {
  status: string;
  processingExpiresAt?: number;
  processedAt?: number;
  createdAt?: number;
  files?: any[];
  restaurantId?: string;
};

const now = Date.now();

function makeFirestore(seed: Record<string, Job>) {
  const store = new Map(Object.entries(seed));
  const drafts = new Map<string, any>();

  return {
    store,
    drafts,
    // Only what routes/tasks uses.
    runTransaction: async (fn: any) => {
      const updatesInTx: any[] = [];
      const tx = {
        get: async () => {
          const data = store.get('job1');
          return { exists: !!data, data: () => data };
        },
        update: async (_ref: any, patch: any) => {
          const current = store.get('job1') ?? {};
          store.set('job1', { ...current, ...patch });
          updatesInTx.push(patch);
        },
      };
      const result = await fn(tx);
      (store as any).txUpdates = updatesInTx;
      return result;
    },
    collection: () => ({
      doc: (id: string) => ({
        get: async () => {
          const data = store.get(id);
          return { exists: !!data, data: () => data };
        },
        update: async (patch: any) => {
          const current = store.get(id) ?? {};
          store.set(id, { ...current, ...patch });
        },
        set: async (value: any) => drafts.set(id, value),
      }),
    }),
  };
}

const makeApp = async (job: Job) => {
  const { tasksRouter } = await import('../src/routes/tasks');
  const firestore = makeFirestore({ job1: job });
  const app: Express = express();
  app.use(express.json());
  app.use(
    tasksRouter({
      firestore: firestore as any,
      storage: { bucket: () => ({ file: () => ({ getSignedUrl: async () => ['http://'] }) }) } as any,
      pubsub: { topic: () => ({ publishMessage: async () => undefined }) } as any,
      bucket: 'b',
      topic: 't',
      signedReadUrls: async () => [],
      requireAuth: (_req, _res, next) => next(),
    }),
  );
  const agent = supertest(app as any);
  return { agent, firestore };
};

const buildMessage = (jobId = 'job1') => ({
  message: { data: Buffer.from(JSON.stringify({ jobId }), 'utf8').toString('base64') },
});

describe('/tasks/process guards', () => {
  it('skips already processed jobs', async () => {
    const { agent, firestore } = await makeApp({ status: 'ready', processedAt: now });
    const res = await agent.post('/tasks/process').send(buildMessage()).expect(200);
    expect(res.body.skipped).toBe(true);
    expect(firestore.store.get('job1')!.status).toBe('ready');
  });

  it('skips active processing window', async () => {
    const { agent, firestore } = await makeApp({
      status: 'processing',
      processingExpiresAt: now + 5 * 60 * 1000,
    });
    const res = await agent.post('/tasks/process').send(buildMessage()).expect(200);
    expect(res.body.skipped).toBe(true);
    expect(firestore.store.get('job1')!.status).toBe('processing');
  });

  it('re-drives expired processing jobs', async () => {
    const { agent, firestore } = await makeApp({
      status: 'processing',
      processingExpiresAt: now - 1,
      files: [],
      restaurantId: 'r1',
    });
    const res = await agent.post('/tasks/process').send(buildMessage()).expect(200);
    expect(res.body.queued).toBe(true);
    const txMerged = Object.assign({}, ...((firestore.store as any).txUpdates ?? []));
    const txUpdate = txMerged;
    expect(txUpdate.status).toBe('processing');
    expect(txUpdate.processingExpiresAt).toBeGreaterThan(now);
  });

  it('transitions queued -> processing and sets expiry', async () => {
    const { agent, firestore } = await makeApp({
      status: 'queued',
      createdAt: now,
      files: [],
      restaurantId: 'r1',
    });
    const res = await agent.post('/tasks/process').send(buildMessage()).expect(200);
    expect(res.body.queued).toBe(true);
    const txMerged = Object.assign({}, ...((firestore.store as any).txUpdates ?? []));
    const txUpdate = txMerged;
    expect(txUpdate.status).toBe('processing');
    expect(txUpdate.processingExpiresAt).toBeGreaterThan(now);
  });

  it('returns 400 when jobId missing', async () => {
    const { agent } = await makeApp({ status: 'queued' });
    await agent.post('/tasks/process').send({}).expect(400);
  });
});
