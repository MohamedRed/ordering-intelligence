import express from 'express';
import request from 'supertest';
import {
  extractBucketKeyFromUrl,
  registerMenuIngestionRoutes,
  resolveMenuPipelineMode,
} from './menu_ingestion_routes';

function makeRouteHarness(session: any) {
  const app = express();
  app.use(express.json());

  const savedFiles: Array<{ key: string; buffer: Buffer; options: Record<string, unknown> }> = [];
  const downloadedKeys: string[] = [];
  const bucket = {
    name: 'menus-bucket',
    file: (key: string) => ({
      download: async () => {
        downloadedKeys.push(key);
        return [Buffer.from(`bytes:${key}`)];
      },
      save: async (buffer: Buffer, options: Record<string, unknown>) => {
        savedFiles.push({ key, buffer, options });
      },
    }),
  };

  const menuDocs = new Map<string, any>();
  const batchWrites: any[] = [];
  const firestore = {
    collection: (name: string) => ({
      doc: (id: string) => ({
        id,
        set: async (payload: any, options?: any) => {
          menuDocs.set(`${name}/${id}`, { payload, options });
        },
      }),
    }),
    batch: () => ({
      set: (ref: any, payload: any, options?: any) => {
        batchWrites.push({ ref, payload, options });
      },
      commit: async () => undefined,
    }),
  };

  const sessionUpdates: any[] = [];
  const sessions = {
    doc: (id: string) => ({
      update: async (payload: any) => {
        sessionUpdates.push({ id, payload });
      },
    }),
  };

  const published: any[] = [];
  const pubsub = {
    topic: (topic: string) => ({
      publishMessage: async (message: any) => {
        published.push({ topic, message });
      },
    }),
  };

  const audits: any[] = [];
  registerMenuIngestionRoutes({
    app,
    firestore: firestore as any,
    sessions: sessions as any,
    pubsub: pubsub as any,
    bucket: bucket as any,
    bucketName: 'menus-bucket',
    menuIngestTopic: 'menu-ingest',
    getSession: async (id: string, res) => {
      if (!session) {
        res.status(404).json({ error: 'session_not_found' });
        return null;
      }
      return { id, ...session };
    },
    audit: async (id: string, event: string, data?: unknown) => {
      audits.push({ id, event, data });
    },
  });

  return { app, audits, batchWrites, downloadedKeys, menuDocs, published, savedFiles, sessionUpdates };
}

describe('menu ingestion onboarding routes', () => {
  it('parses supported GCS URL forms', () => {
    expect(extractBucketKeyFromUrl('https://storage.googleapis.com/bucket-a/path/to/menu.jpg')).toEqual({
      bucket: 'bucket-a',
      key: 'path/to/menu.jpg',
    });
    expect(extractBucketKeyFromUrl('https://bucket-b.storage.googleapis.com/menu-flyers/a.jpg?x=1')).toEqual({
      bucket: 'bucket-b',
      key: 'menu-flyers/a.jpg',
    });
    expect(extractBucketKeyFromUrl('notaurl')).toEqual({});
  });

  it('keeps full ingestion as the default mode and rejects unknown modes', () => {
    expect(resolveMenuPipelineMode(undefined)).toBe('full');
    expect(resolveMenuPipelineMode('menu_only')).toBe('menu_only');
    expect(resolveMenuPipelineMode('unexpected')).toBe('menu_only');
  });

  it('starts ingestion by copying flyers and publishing a menu job', async () => {
    const { app, audits, downloadedKeys, menuDocs, published, savedFiles, sessionUpdates } = makeRouteHarness({
      flyers: ['https://storage.googleapis.com/menus-bucket/menu-flyers/menu.png'],
      tenant: { store_id: 'store-123' },
    });

    const res = await request(app).post('/onboarding-sessions/session-1/ingest-menu').send({}).expect(200);
    const jobId = res.body.job_id;

    expect(jobId).toMatch(/[a-f0-9-]{36}/);
    expect(downloadedKeys).toEqual(['menu-flyers/menu.png']);
    expect(savedFiles).toHaveLength(1);
    expect(savedFiles[0].key).toBe(`menu-raw/store-123/${jobId}/page-1.png`);
    expect(savedFiles[0].options).toMatchObject({ contentType: 'image/png', resumable: false });
    expect(menuDocs.get(`menus_ingest/${jobId}`).payload).toMatchObject({
      jobId,
      restaurantId: 'store-123',
      status: 'queued',
      pipelineMode: 'full',
      files: [`menu-raw/store-123/${jobId}/page-1.png`],
    });
    expect(published).toEqual([{ topic: 'menu-ingest', message: { json: { jobId } } }]);
    expect(sessionUpdates[0].payload.ingestion).toEqual({
      job_ids: [jobId],
      status: 'queued',
      fast_ready: false,
    });
    expect(audits[0]).toMatchObject({
      id: 'session-1',
      event: 'ingest_triggered',
      data: { jobId, restaurantId: 'store-123', fileCount: 1 },
    });
  });

  it('rejects ingestion when no flyers are attached', async () => {
    const { app } = makeRouteHarness({ flyers: [] });
    const res = await request(app).post('/onboarding-sessions/session-1/ingest-menu').send({}).expect(400);
    expect(res.body.error).toBe('no_flyers');
  });

  it('rejects unsupported flyer file types before publishing ingestion', async () => {
    const { app, published, savedFiles } = makeRouteHarness({
      flyers: ['https://storage.googleapis.com/menus-bucket/menu-flyers/menu.pdf'],
      tenant: { store_id: 'store-123' },
    });

    const res = await request(app).post('/onboarding-sessions/session-1/ingest-menu').send({}).expect(400);

    expect(res.body.error).toBe('unsupported_menu_flyer_type');
    expect(savedFiles).toHaveLength(0);
    expect(published).toHaveLength(0);
  });

  it('resumes image enrichment and cancels existing jobs', async () => {
    const harness = makeRouteHarness({
      ingestion: { job_ids: ['job-a', 'job-b'], fast_ready: true },
    });

    await request(harness.app).post('/onboarding-sessions/session-1/ingest-menu/resume-images').send({}).expect(200);
    expect(harness.menuDocs.get('menus_ingest/job-b').payload).toMatchObject({
      jobId: 'job-b',
      status: 'queued',
      pipelineMode: 'full',
      progressStage: 'queued',
      progressPercent: 0,
    });
    expect(harness.sessionUpdates[0].payload.ingestion).toEqual({
      job_ids: ['job-a', 'job-b'],
      status: 'queued',
      fast_ready: true,
    });

    await request(harness.app).post('/onboarding-sessions/session-1/cancel-ingest').send({}).expect(200);
    expect(harness.batchWrites).toHaveLength(2);
    expect(harness.batchWrites.map((write) => write.payload.status)).toEqual(['canceled', 'canceled']);
    expect(harness.sessionUpdates[1].payload.ingestion).toEqual({
      job_ids: ['job-a', 'job-b'],
      status: 'canceled',
    });
  });
});
