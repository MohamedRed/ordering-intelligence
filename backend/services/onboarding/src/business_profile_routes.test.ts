import express from 'express';
import request from 'supertest';
import { generateBusinessPrefill, registerBusinessProfileRoutes } from './business_profile_routes';

function makeVertex(text: string) {
  const generateContent = jest.fn(async () => ({
    response: {
      candidates: [
        {
          content: {
            parts: [{ text }],
          },
        },
      ],
    },
  }));
  return {
    vertex: {
      getGenerativeModel: jest.fn(() => ({ generateContent })),
    },
    generateContent,
  };
}

function makeHarness(params: { session?: any; vertex?: any } = {}) {
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

  registerBusinessProfileRoutes({
    app,
    sessions: sessions as any,
    vertex: 'vertex' in params ? params.vertex : makeVertex('{"business_name":"Demo"}').vertex,
    prefillModel: 'test-model',
    getSession: async (id, res) => {
      if (params.session === null) {
        res.status(404).json({ error: 'session_not_found' });
        return null;
      }
      return { id, flyers: ['https://example.test/menu.jpg'], ...(params.session ?? {}) };
    },
    audit: async (id, event, data) => {
      audits.push({ id, event, data });
    },
  });

  return { app, audits, updates };
}

describe('business profile routes', () => {
  it('generates structured prefill from flyer URLs', async () => {
    const { vertex, generateContent } = makeVertex('Here is JSON {"business_name":"Chez Test","phone":"+1555"}');
    const prefill = await generateBusinessPrefill(vertex, 'prefill-model', ['https://example.test/menu.jpg']);

    expect(prefill).toEqual({
      model: 'prefill-model',
      raw: 'Here is JSON {"business_name":"Chez Test","phone":"+1555"}',
      parsed: { business_name: 'Chez Test', phone: '+1555' },
    });
    expect(generateContent).toHaveBeenCalledWith(
      expect.objectContaining({
        generationConfig: { temperature: 0.2, maxOutputTokens: 512 },
      }),
    );
  });

  it('stores generated prefill and audits the session', async () => {
    const { vertex } = makeVertex('{"business_name":"Demo"}');
    const { app, audits, updates } = makeHarness({ vertex });

    const res = await request(app).post('/onboarding-sessions/session-1/prefill').send({}).expect(200);

    expect(res.body.prefill.parsed).toEqual({ business_name: 'Demo' });
    expect(updates[0].payload).toMatchObject({
      status: 'prefill_ready',
      prefill: { model: 'test-model', parsed: { business_name: 'Demo' } },
    });
    expect(audits).toEqual([{ id: 'session-1', event: 'prefill_generated', data: undefined }]);
  });

  it('returns existing prefill dependency and input errors', async () => {
    const vertexRes = await request(makeHarness({ vertex: null }).app)
      .post('/onboarding-sessions/session-1/prefill')
      .send({})
      .expect(500);
    expect(vertexRes.body.error).toBe('vertex_not_configured');

    const flyersRes = await request(makeHarness({ session: { flyers: [] } }).app)
      .post('/onboarding-sessions/session-1/prefill')
      .send({})
      .expect(400);
    expect(flyersRes.body.error).toBe('no_flyers');
  });

  it('updates business details and audits the payload', async () => {
    const { app, audits, updates } = makeHarness();
    const payload = { name: 'Demo', type: 'fast_food' };

    await request(app).patch('/onboarding-sessions/session-1/business-details').send(payload).expect(200);

    expect(updates[0].payload.business).toEqual(payload);
    expect(updates[0].payload.updated_at).toBeDefined();
    expect(audits).toEqual([{ id: 'session-1', event: 'business_updated', data: payload }]);
  });
});
