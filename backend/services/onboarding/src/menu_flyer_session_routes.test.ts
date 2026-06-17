import express from 'express';
import request from 'supertest';
import { registerMenuFlyerSessionRoutes } from './menu_flyer_session_routes';

function makeHarness(session: any = {}) {
  const app = express();
  app.use(express.json());

  const updates: Array<{ id: string; payload: any }> = [];
  const audits: Array<{ id: string; event: string; data?: unknown }> = [];
  const sessions = {
    doc: (id: string) => ({
      update: async (payload: any) => {
        updates.push({ id, payload });
      },
    }),
  };

  registerMenuFlyerSessionRoutes({
    app,
    sessions: sessions as any,
    getSession: async (id, res) => {
      if (!session) {
        res.status(404).json({ error: 'session_not_found' });
        return null;
      }
      return { id, ...session };
    },
    audit: async (id, event, data) => {
      audits.push({ id, event, data });
    },
  });

  return { app, audits, updates };
}

describe('menu flyer session routes', () => {
  it('attaches menu flyer URLs and records audit metadata', async () => {
    const { app, audits, updates } = makeHarness();

    await request(app)
      .patch('/onboarding-sessions/session-1/menu-flyers')
      .send({ urls: [' https://example.test/menu-a.jpg ', 'https://example.test/menu-b.jpg'] })
      .expect(200);

    expect(updates).toHaveLength(1);
    expect(updates[0].id).toBe('session-1');
    expect(updates[0].payload.flyers).toBeDefined();
    expect(updates[0].payload.updated_at).toBeDefined();
    expect(audits).toEqual([
      {
        id: 'session-1',
        event: 'flyers_attached',
        data: { urls: ['https://example.test/menu-a.jpg', 'https://example.test/menu-b.jpg'] },
      },
    ]);
  });

  it('detaches menu flyer URLs and records audit metadata', async () => {
    const { app, audits, updates } = makeHarness();

    await request(app)
      .delete('/onboarding-sessions/session-1/menu-flyers')
      .send({ urls: ['https://example.test/menu-a.jpg'] })
      .expect(200);

    expect(updates).toHaveLength(1);
    expect(updates[0].payload.flyers).toBeDefined();
    expect(audits).toEqual([
      {
        id: 'session-1',
        event: 'flyers_detached',
        data: { urls: ['https://example.test/menu-a.jpg'] },
      },
    ]);
  });

  it('rejects empty flyer URL payloads before loading a session', async () => {
    const { app, updates, audits } = makeHarness();

    const res = await request(app)
      .patch('/onboarding-sessions/session-1/menu-flyers')
      .send({ urls: [] })
      .expect(400);

    expect(res.body.error).toBe('urls_required');
    expect(updates).toHaveLength(0);
    expect(audits).toHaveLength(0);
  });

  it('returns the shared session 404 when the session is missing', async () => {
    const { app, updates, audits } = makeHarness(null);

    const res = await request(app)
      .delete('/onboarding-sessions/missing/menu-flyers')
      .send({ urls: ['https://example.test/menu.jpg'] })
      .expect(404);

    expect(res.body.error).toBe('session_not_found');
    expect(updates).toHaveLength(0);
    expect(audits).toHaveLength(0);
  });
});
