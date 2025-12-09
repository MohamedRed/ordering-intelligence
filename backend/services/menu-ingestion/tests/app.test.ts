import { jest } from '@jest/globals';
import express, { type Express } from 'express';
import supertest from 'supertest';
import { ingestRouter } from '../src/routes/ingest';

process.env.MENU_BUCKET = 'test-bucket';
process.env.MENU_INGEST_TOPIC = 'test-topic';
process.env.VERTEX_PROJECT = 'test-project';
process.env.IMAGE_REGION = 'global';
process.env.GOOGLE_CLOUD_PROJECT = 'test-project';

let docExists = false;
let docData: any = {};
const docGetMock = jest.fn(async () => ({ exists: docExists, data: () => docData }));

const setupMocks = async () => {
  await jest.unstable_mockModule('@google-cloud/storage', () => ({
    Storage: class Storage {
      bucket() {
        return {
          file: () => ({
            getSignedUrl: async () => ['http://example'],
          }),
        };
      }
    },
  }));

  await jest.unstable_mockModule('@google-cloud/pubsub', () => ({
    PubSub: class PubSub {
      topic() {
        return { publishMessage: async () => undefined };
      }
    },
  }));

  await jest.unstable_mockModule('@google-cloud/firestore', () => ({
    Firestore: class Firestore {
      collection() {
        return {
          orderBy: () => ({ limit: () => ({ get: async () => ({ docs: [] }) }) }),
          limit: () => ({ get: async () => ({ docs: [] }) }),
          get: async () => ({ docs: [] }),
          doc: () => ({
            get: docGetMock,
            set: async () => undefined,
            update: async () => undefined,
          }),
        };
      }
      doc() {
        return this.collection();
      }
    },
  }));

  await jest.unstable_mockModule('@google-cloud/vertexai', () => ({
    VertexAI: class VertexAI {
      constructor() {}
      getGenerativeModel() {
        return {
          generateContent: async () => ({
            response: {
              candidates: [],
            },
          }),
        };
      }
    },
  }));

  await jest.unstable_mockModule('google-auth-library', () => ({
    GoogleAuth: class GoogleAuth {
      constructor() {}
      getAccessToken() {
        return Promise.resolve('token');
      }
    },
  }));

  await jest.unstable_mockModule('firebase-admin/app', () => ({
    initializeApp: () => undefined,
    applicationDefault: () => ({}),
  }));

  await jest.unstable_mockModule('firebase-admin/auth', () => ({
    getAuth: () => ({
      verifyIdToken: async () => ({ uid: 'test' }),
    }),
  }));
};

let app: Express;
let requestAgent: any;

const resetDoc = () => {
  docExists = false;
  docData = {};
  docGetMock.mockClear();
};

describe('app routers', () => {
  beforeAll(async () => {
    await setupMocks();
    const importedApp = await import('../src/app');
    app = importedApp.default;
    requestAgent = supertest(app as any);
  });

  beforeEach(() => {
    resetDoc();
  });

  it('exposes health endpoint', async () => {
    await requestAgent.get('/health').expect(200).expect({ ok: true });
  });
});

const makeIngestApp = (exists: boolean) => {
  const storage = {
    bucket: () => ({
      file: () => ({ getSignedUrl: async () => ['http://example'] }),
    }),
  } as any;
  const pubsub = {
    topic: () => ({ publishMessage: async () => undefined }),
  } as any;
  const firestore = {
    collection: () => ({
      doc: () => ({
        get: async () => ({ exists, data: () => ({ jobId: '123', restaurantId: 'z' }) }),
        set: async () => undefined,
        update: async () => undefined,
      }),
    }),
  } as any;
  const ctx = {
    firestore,
    storage,
    pubsub,
    bucket: 'test',
    topic: 'test-topic',
    signedReadUrls: async () => [],
    requireAuth: (_req: any, _res: any, next: any) => next(),
  } as any;
  const server = express();
  server.use(express.json());
  server.use(ingestRouter(ctx));
  return server;
};

describe('ingest router standalone', () => {
  it('returns urls for start request', async () => {
    const server = makeIngestApp(false);
    const res = await supertest(server)
      .post('/ingest/start')
      .send({ restaurantId: 'foo', pageCount: 2 })
      .expect(200);
    expect(res.body.uploadUrls).toHaveLength(2);
  });

  it('submit 404 when job missing', async () => {
    const server = makeIngestApp(false);
    await supertest(server).post('/ingest/submit').send({ jobId: 'foo' }).expect(404);
  });

  it('submit queued when job exists', async () => {
    const server = makeIngestApp(true);
    const res = await supertest(server).post('/ingest/submit').send({ jobId: 'foo' }).expect(200);
    expect(res.body.status).toBe('queued');
  });
});
