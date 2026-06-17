import express, { type Express } from 'express';
import supertest from 'supertest';
import { cleanupRouter } from '../src/routes/cleanup';

type Job = { status: string; processingExpiresAt?: number; issues?: string[] };

function makeFirestore(docs: Record<string, Job>) {
  const store = new Map(Object.entries(docs));
  const matchesFilters = (data: Job, filters: Array<{ field: keyof Job; op: string; value: unknown }>) =>
    filters.every((filter) => {
      const actual = data[filter.field];
      if (filter.op === '<') return typeof actual === 'number' && actual < Number(filter.value);
      if (filter.op === '==') return actual === filter.value;
      throw new Error(`unsupported mock operator: ${filter.op}`);
    });
  const makeQuery = (filters: Array<{ field: keyof Job; op: string; value: unknown }> = []) => ({
    where: (field: keyof Job, op: string, value: unknown) => makeQuery(filters.concat({ field, op, value })),
    limit: () => ({
      get: async () => ({
        forEach: (cb: (doc: any) => void) => {
          for (const [id, data] of store.entries()) {
            if (!matchesFilters(data, filters)) continue;
            cb({
              id,
              data: () => data,
              ref: { id },
            });
          }
        },
      }),
    }),
    doc: (id: string) => ({
      update: async (patch: any) => {
        const current = store.get(id) ?? {};
        store.set(id, { ...current, ...patch });
      },
    }),
  });

  return {
    store,
    collection: () => makeQuery(),
    batch: () => {
      const updates: Array<{ ref: any; data: any }> = [];
      return {
        update: (ref: any, data: any) => updates.push({ ref, data }),
        commit: async () => {
          updates.forEach(({ ref, data }) => {
            const current = store.get(ref.id) ?? {};
            store.set(ref.id, { ...current, ...data });
          });
        },
      };
    },
  };
}

const makeApp = (firestore: any): Express => {
  const app = express();
  app.use(express.json());
  app.use(
    cleanupRouter({
      firestore: firestore as any,
      storage: {} as any,
      pubsub: {} as any,
      bucket: 'b',
      topic: 't',
      signedReadUrls: async () => [],
      requireAuth: (_req, _res, next) => next(),
    }),
  );
  return app;
};

describe('/tasks/cleanup', () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('resets expired processing jobs to queued', async () => {
    const now = 1_700_000_000_000;
    jest.spyOn(Date, 'now').mockReturnValue(now);
    const firestore = makeFirestore({
      j1: { status: 'processing', processingExpiresAt: now - 1000, issues: [] },
      j2: { status: 'processing', processingExpiresAt: now + 1000, issues: [] },
      j3: { status: 'ready', processingExpiresAt: now - 1000, issues: [] },
    });
    const app = makeApp(firestore);
    const res = await supertest(app).post('/tasks/cleanup').send({}).expect(200);

    expect(res.body.reset).toBe(1);
    const updated = firestore.store.get('j1')!;
    expect(updated.status).toBe('queued');
    expect((updated.issues ?? []).includes('reset by cleanup')).toBe(true);
    expect(firestore.store.get('j2')!.status).toBe('processing');
    expect(firestore.store.get('j3')!.status).toBe('ready');
  });
});
