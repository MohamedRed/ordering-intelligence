import { jest } from '@jest/globals';
import express, { type Express } from 'express';
import supertest from 'supertest';
type IngestRouter = typeof import('../src/routes/ingest').ingestRouter;

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
    OAuth2Client: class OAuth2Client {
      verifyIdToken() {
        return Promise.resolve({ getPayload: () => ({ email: 'menu-ingestion@example.test' }) });
      }
    },
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
let ingestRouter: IngestRouter;

beforeAll(async () => {
  await setupMocks();
  const [importedApp, importedIngest] = await Promise.all([
    import('../src/app'),
    import('../src/routes/ingest'),
  ]);
  app = importedApp.default;
  requestAgent = supertest(app as any);
  ingestRouter = importedIngest.ingestRouter;
});

const resetDoc = () => {
  docExists = false;
  docData = {};
  docGetMock.mockClear();
};

const googleOidcEnvKeys = [
  'ALLOW_GOOGLE_ID_TOKENS',
  'GOOGLE_ID_TOKEN_AUDIENCES',
  'INTERNAL_AUTH_AUDIENCE',
  'GOOGLE_ID_TOKEN_ALLOWED_EMAILS',
  'INTERNAL_ALLOWED_EMAILS',
];

async function importAppWithGoogleOidcEnv(env: Record<string, string | undefined>) {
  const previous = new Map(googleOidcEnvKeys.map((key) => [key, process.env[key]]));
  for (const key of googleOidcEnvKeys) {
    const value = env[key];
    if (value == null) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  }

  jest.resetModules();
  await setupMocks();
  try {
    return await import('../src/app');
  } finally {
    for (const [key, value] of previous.entries()) {
      if (value == null) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
    jest.resetModules();
  }
}

describe('app routers', () => {
  beforeEach(() => {
    resetDoc();
  });

  it('exposes health endpoint', async () => {
    await requestAgent.get('/health').expect(200).expect({ ok: true });
  });

  it('requires auth for ingest job creation', async () => {
    const res = await requestAgent
      .post('/ingest/start')
      .set('Origin', 'https://admin.example.test')
      .send({ restaurantId: 'foo', pageCount: 1 })
      .expect(401);
    expect(res.body.error).toBe('missing bearer token');
    expect(res.headers['access-control-allow-origin']).toBe('https://admin.example.test');
  });

  it('rejects disallowed browser origins when configured', async () => {
    process.env.MENU_INGESTION_CORS_ORIGINS = 'https://admin.example.test';
    jest.resetModules();
    await setupMocks();
    const importedApp = await import('../src/app');
    await supertest(importedApp.default as any)
      .options('/ingest/start')
      .set('Origin', 'https://evil.example.test')
      .expect(403);
    delete process.env.MENU_INGESTION_CORS_ORIGINS;
  });
});

describe('Google OIDC startup validation', () => {
  it('requires explicit audiences when Google ID tokens are enabled', async () => {
    await expect(
      importAppWithGoogleOidcEnv({
        ALLOW_GOOGLE_ID_TOKENS: 'true',
        GOOGLE_ID_TOKEN_ALLOWED_EMAILS: 'menu-ingestion@example.test',
      }),
    ).rejects.toThrow(/GOOGLE_ID_TOKEN_AUDIENCES or INTERNAL_AUTH_AUDIENCE/);
  });

  it('requires an explicit service account allowlist when Google ID tokens are enabled', async () => {
    await expect(
      importAppWithGoogleOidcEnv({
        ALLOW_GOOGLE_ID_TOKENS: 'true',
        GOOGLE_ID_TOKEN_AUDIENCES: 'https://menu-ingestion.example.test',
      }),
    ).rejects.toThrow(/GOOGLE_ID_TOKEN_ALLOWED_EMAILS or INTERNAL_ALLOWED_EMAILS/);
  });

  it('accepts shared internal auth aliases for Google ID token configuration', async () => {
    await expect(
      importAppWithGoogleOidcEnv({
        ALLOW_GOOGLE_ID_TOKENS: 'true',
        INTERNAL_AUTH_AUDIENCE: 'https://menu-ingestion.example.test',
        INTERNAL_ALLOWED_EMAILS: 'menu-ingestion@example.test',
      }),
    ).resolves.toBeDefined();
  });
});

const makeIngestApp = (
  exists: boolean,
  jobData: Record<string, unknown> = { jobId: '123', restaurantId: 'z', status: 'uploading' },
) => {
  const updateMock = jest.fn(async () => undefined);
  const publishMessageMock = jest.fn(async () => undefined);
  const storage = {
    bucket: () => ({
      file: () => ({ getSignedUrl: async () => ['http://example'] }),
    }),
  } as any;
  const pubsub = {
    publishMessageMock,
    topic: () => ({ publishMessage: publishMessageMock }),
  } as any;
  const firestore = {
    updateMock,
    collection: () => ({
      doc: () => ({
        get: async () => ({ exists, data: () => jobData }),
        set: async () => undefined,
        update: updateMock,
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
  return { server, firestore, pubsub };
};

describe('ingest router standalone', () => {
  it('returns urls for start request', async () => {
    const { server } = makeIngestApp(false);
    const res = await supertest(server)
      .post('/ingest/start')
      .send({ restaurantId: 'foo', pageCount: 2 })
      .expect(200);
    expect(res.body.uploadUrls).toHaveLength(2);
  });

  it('rejects start requests above the page limit', async () => {
    const { server } = makeIngestApp(false);
    const res = await supertest(server)
      .post('/ingest/start')
      .send({ restaurantId: 'foo', pageCount: 6 })
      .expect(400);
    expect(res.body.error).toBe('too_many_pages');
    expect(res.body.maxPages).toBe(5);
  });

  it('submit 404 when job missing', async () => {
    const { server } = makeIngestApp(false);
    await supertest(server).post('/ingest/submit').send({ jobId: 'foo' }).expect(404);
  });

  it('submit queued when job exists', async () => {
    const { server, firestore, pubsub } = makeIngestApp(true);
    const res = await supertest(server).post('/ingest/submit').send({ jobId: 'foo' }).expect(200);
    expect(res.body.status).toBe('queued');
    expect(firestore.updateMock).toHaveBeenCalledWith(expect.objectContaining({
      status: 'queued',
      progressStage: 'queued',
      progressPercent: 0,
    }));
    expect(pubsub.publishMessageMock).toHaveBeenCalledWith({ json: { jobId: 'foo' } });
  });

  it('submit is idempotent for queued and processing jobs', async () => {
    for (const status of ['queued', 'processing']) {
      const { server, firestore, pubsub } = makeIngestApp(true, { jobId: 'foo', restaurantId: 'z', status });
      const res = await supertest(server).post('/ingest/submit').send({ jobId: 'foo' }).expect(200);
      expect(res.body).toEqual({ jobId: 'foo', status });
      expect(firestore.updateMock).not.toHaveBeenCalled();
      expect(pubsub.publishMessageMock).not.toHaveBeenCalled();
    }
  });

  it('submit rejects terminal jobs', async () => {
    const ready = makeIngestApp(true, { jobId: 'foo', restaurantId: 'z', status: 'ready' });
    await supertest(ready.server)
      .post('/ingest/submit')
      .send({ jobId: 'foo' })
      .expect(409)
      .expect(({ body }) => expect(body.error).toBe('job_already_ready'));

    const canceled = makeIngestApp(true, { jobId: 'foo', restaurantId: 'z', status: 'canceled' });
    await supertest(canceled.server)
      .post('/ingest/submit')
      .send({ jobId: 'foo' })
      .expect(409)
      .expect(({ body }) => expect(body.error).toBe('job_canceled'));
  });
});
