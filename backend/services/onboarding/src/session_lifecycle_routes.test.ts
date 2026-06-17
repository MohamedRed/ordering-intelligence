import express from 'express';
import request from 'supertest';
import { registerSessionLifecycleRoutes } from './session_lifecycle_routes';

function makeCollection(initial: Record<string, any> = {}) {
  const docs = new Map(Object.entries(initial));
  const sets: Array<{ id: string; payload: any; options?: any }> = [];
  const updates: Array<{ id: string; payload: any }> = [];

  return {
    docs,
    sets,
    updates,
    collection: {
      doc: (id: string) => ({
        get: async () => {
          const data = docs.get(id);
          return {
            exists: data !== undefined,
            data: () => data,
          };
        },
        set: async (payload: any, options?: any) => {
          sets.push({ id, payload, options });
          docs.set(id, { ...(options?.merge ? docs.get(id) ?? {} : {}), ...payload });
        },
        update: async (payload: any) => {
          updates.push({ id, payload });
          docs.set(id, { ...(docs.get(id) ?? {}), ...payload });
        },
      }),
    },
  };
}

function makeHarness(params: {
  sessions?: Record<string, any>;
  tenants?: Record<string, any>;
  createSessionId?: () => string;
} = {}) {
  const app = express();
  app.use(express.json());

  const sessions = makeCollection(params.sessions);
  const tenants = makeCollection(params.tenants);
  const audits: Array<{ id: string; event: string; data?: unknown }> = [];

  registerSessionLifecycleRoutes({
    app,
    sessions: sessions.collection as any,
    tenants: tenants.collection as any,
    createSessionId: params.createSessionId,
    getSession: async (id, res) => {
      const data = sessions.docs.get(id);
      if (!data) {
        res.status(404).json({ error: 'session_not_found' });
        return null;
      }
      return { id, ...data };
    },
    audit: async (id, event, data) => {
      audits.push({ id, event, data });
    },
  });

  return { app, audits, sessions, tenants };
}

describe('session lifecycle onboarding routes', () => {
  it('returns tenant state with the active session payload when available', async () => {
    const { app } = makeHarness({
      tenants: {
        'tenant-1': {
          active_session_id: 'session-active',
          last_session_id: 'session-last',
          store_id: 'store-1',
        },
      },
      sessions: {
        'session-active': { status: 'collecting', business: { name: 'Demo' } },
      },
    });

    const res = await request(app).get('/onboarding-tenants/tenant-1').expect(200);

    expect(res.body).toEqual({
      tenant_id: 'tenant-1',
      active_session_id: 'session-active',
      last_session_id: 'session-last',
      store_id: 'store-1',
      session: {
        session_id: 'session-active',
        status: 'collecting',
        business: { name: 'Demo' },
      },
    });
  });

  it('returns tenant lookup errors', async () => {
    const { app } = makeHarness();

    const res = await request(app).get('/onboarding-tenants/missing-tenant').expect(404);

    expect(res.body.error).toBe('tenant_not_found');
  });

  it('reuses an active tenant session that is not terminal', async () => {
    const { app, audits, sessions, tenants } = makeHarness({
      tenants: { 'tenant-1': { active_session_id: 'session-active' } },
      sessions: { 'session-active': { status: 'ingesting' } },
      createSessionId: () => 'session-new',
    });

    const res = await request(app)
      .post('/onboarding-sessions')
      .send({ tenant_id: ' tenant-1 ', store_id: ' store-1 ' })
      .expect(201);

    expect(res.body).toEqual({ session_id: 'session-active', reused: true });
    expect(sessions.sets).toEqual([]);
    expect(tenants.sets).toEqual([]);
    expect(audits).toEqual([]);
  });

  it('creates a new tenant session and updates tenant resume state', async () => {
    const { app, audits, sessions, tenants } = makeHarness({
      tenants: { 'tenant-1': { active_session_id: 'session-ready' } },
      sessions: { 'session-ready': { status: 'ready' } },
      createSessionId: () => 'session-new',
    });

    const res = await request(app)
      .post('/onboarding-sessions')
      .send({ tenant_id: 'tenant-1', store_id: 'store-1' })
      .expect(201);

    expect(res.body).toEqual({ session_id: 'session-new', reused: false });
    expect(sessions.sets[0]).toMatchObject({
      id: 'session-new',
      payload: {
        status: 'collecting',
        business: {},
        flyers: [],
        audit: [],
        tenant: { tenant_id: 'tenant-1', store_id: 'store-1' },
      },
    });
    expect(tenants.sets[0]).toMatchObject({
      id: 'tenant-1',
      payload: {
        active_session_id: 'session-new',
        last_session_id: 'session-new',
        store_id: 'store-1',
      },
      options: { merge: true },
    });
    expect(audits).toEqual([
      {
        id: 'session-new',
        event: 'session_created',
        data: { tenant_id: 'tenant-1', store_id: 'store-1' },
      },
    ]);
  });

  it('updates notification preferences and audits the session', async () => {
    const { app, audits, sessions } = makeHarness({
      sessions: { 'session-1': { status: 'collecting' } },
    });

    const payload = { device_tokens: ['token-a'], webhook_url: 'https://example.test/hook' };
    await request(app).post('/onboarding-sessions/session-1/notifications').send(payload).expect(200);

    expect(sessions.updates[0].payload.notifications).toEqual(payload);
    expect(sessions.updates[0].payload.updated_at).toBeDefined();
    expect(audits).toEqual([{ id: 'session-1', event: 'notifications_set', data: payload }]);
  });
});
