import express from 'express';
import request from 'supertest';
import { registerFinalizeRoutes } from './finalize_routes';

function readySession(overrides: any = {}) {
  return {
    business: {
      name: 'Demo Pizza',
      phone: '+15551230000',
      address: '123 Main St',
      timezone: 'America/Los_Angeles',
      type: 'fast_food',
      currency: 'USD',
      fuelDefaultPrepayCents: 1500,
    },
    flyers: ['https://example.test/menu.jpg'],
    stripe: { account_id: 'acct_123', status: 'active' },
    twilio: { number: '+15551230000', sid: 'PN123', elevenlabs_phone_number_id: 'elpn_123' },
    ingestion: { status: 'succeeded', job_ids: ['job-1'] },
    agent: { template_agent_id: 'template-fast', voice_id: 'voice-1', branch_id: 'branch-1' },
    tenant: { tenant_id: 'tenant-1', store_id: 'store-1' },
    ...overrides,
  };
}

function makeCollection(initial: Record<string, any> = {}) {
  const docs = new Map(Object.entries(initial));
  const sets: Array<{ collection?: string; id: string; payload: any; options?: any }> = [];
  const updates: Array<{ id: string; payload: any }> = [];

  return {
    docs,
    sets,
    updates,
    collection: {
      doc: (id: string) => ({
        get: async () => {
          const data = docs.get(id);
          return { exists: data !== undefined, data: () => data };
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

function makeFirestore(initial: Record<string, Record<string, any>> = {}) {
  const sets: Array<{ collection: string; id: string; payload: any; options?: any }> = [];
  const collections = new Map<string, Map<string, any>>();
  for (const [name, docs] of Object.entries(initial)) {
    collections.set(name, new Map(Object.entries(docs)));
  }

  return {
    sets,
    firestore: {
      collection: (name: string) => ({
        doc: (id: string) => ({
          get: async () => {
            const data = collections.get(name)?.get(id);
            return { exists: data !== undefined, data: () => data };
          },
          set: async (payload: any, options?: any) => {
            sets.push({ collection: name, id, payload, options });
            const docs = collections.get(name) ?? new Map<string, any>();
            docs.set(id, { ...(options?.merge ? docs.get(id) ?? {} : {}), ...payload });
            collections.set(name, docs);
          },
        }),
      }),
    },
  };
}

function makeHarness(params: {
  session?: any;
  firestoreDocs?: Record<string, Record<string, any>>;
  allowDemoSkipStripe?: boolean;
  upsertPhoneNumberRoute?: jest.Mock;
} = {}) {
  const app = express();
  app.use(express.json());

  const { firestore, sets: firestoreSets } = makeFirestore(params.firestoreDocs);
  const sessions = makeCollection({ 'session-1': params.session ?? readySession() });
  const onboardingTenants = makeCollection();
  const audits: Array<{ id: string; event: string; data?: unknown }> = [];
  const upsertPhoneNumberRoute = params.upsertPhoneNumberRoute ?? jest.fn(async () => undefined);

  registerFinalizeRoutes({
    app,
    firestore: firestore as any,
    sessions: sessions.collection as any,
    onboardingTenants: onboardingTenants.collection as any,
    allowDemoSkipStripe: params.allowDemoSkipStripe ?? false,
    demoSkipStripeFlag: 'demo_skip_stripe',
    upsertPhoneNumberRoute,
    maskPhone: (phone) => (phone ? `masked:${phone}` : ''),
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

  return { app, audits, firestoreSets, onboardingTenants, sessions, upsertPhoneNumberRoute };
}

describe('finalize onboarding route', () => {
  it('rejects sessions that are missing required readiness fields', async () => {
    const { app } = makeHarness({
      session: {
        business: {},
        flyers: [],
        stripe: { status: 'disabled' },
        twilio: {},
        ingestion: { status: 'queued' },
        agent: {},
      },
    });

    const res = await request(app).post('/onboarding-sessions/session-1/finalize').send({}).expect(400);

    expect(res.body).toEqual({
      error: 'not_ready',
      missing: ['business.name', 'flyers', 'twilio.number', 'stripe_kyc', 'ingestion', 'agent'],
    });
  });

  it('writes tenant and store records, finalizes routing, and completes onboarding state', async () => {
    const { app, audits, firestoreSets, onboardingTenants, sessions, upsertPhoneNumberRoute } = makeHarness();

    const res = await request(app).post('/onboarding-sessions/session-1/finalize').send({}).expect(200);

    expect(res.body).toEqual({ status: 'ready', tenant_id: 'tenant-1', store_id: 'store-1' });
    expect(firestoreSets[0]).toMatchObject({
      collection: 'tenants',
      id: 'tenant-1',
      payload: {
        name: 'Demo Pizza',
        phone: '+15551230000',
        address: '123 Main St',
        timezone: 'America/Los_Angeles',
        stripe_account_id: 'acct_123',
        status: 'ready',
      },
      options: { merge: true },
    });
    expect(firestoreSets[1].collection).toBe('stores');
    expect(firestoreSets[1].payload).toMatchObject({
      store_id: 'store-1',
      tenant_id: 'tenant-1',
      business_type: 'fast_food',
      currency: 'USD',
      fuel_default_prepay_cents: 1500,
      menu_job_ids: ['job-1'],
      elevenlabs_agent_template_id: 'template-fast',
      elevenlabs_agent_mode: 'shared_template',
      twilio_number: '+15551230000',
      elevenlabs_phone_number_id: 'elpn_123',
      elevenlabs_variables: { tenantId: 'tenant-1', storeId: 'store-1', businessType: 'fast_food' },
    });
    expect(firestoreSets[1].payload.order_comms.statuses.ready.templates[0].body).toBe(
      'Your order is ready for pickup.',
    );
    expect(upsertPhoneNumberRoute).toHaveBeenCalledWith({
      onboardingSessionId: 'session-1',
      toNumber: '+15551230000',
      elevenlabsPhoneNumberId: 'elpn_123',
      twilioSid: 'PN123',
      tenantId: 'tenant-1',
      storeId: 'store-1',
      businessType: 'fast_food',
      routeStatus: 'ready',
      source: 'onboarding_finalize',
    });
    expect(sessions.updates[0].payload).toMatchObject({
      status: 'ready',
      tenant: { tenant_id: 'tenant-1', store_id: 'store-1' },
    });
    expect(onboardingTenants.sets[0]).toMatchObject({
      id: 'tenant-1',
      payload: { last_session_id: 'session-1', store_id: 'store-1' },
      options: { merge: true },
    });
    expect(onboardingTenants.sets[0].payload.active_session_id).toBeDefined();
    expect(audits).toEqual([
      {
        id: 'session-1',
        event: 'phone_number_route_finalized',
        data: { tenant_id: 'tenant-1', store_id: 'store-1', to_number: 'masked:+15551230000' },
      },
      {
        id: 'session-1',
        event: 'finalized',
        data: { tenant_id: 'tenant-1', store_id: 'store-1' },
      },
    ]);
  });

  it('allows configured demo tenants to finalize without Stripe readiness', async () => {
    const { app, audits } = makeHarness({
      allowDemoSkipStripe: true,
      firestoreDocs: {
        tenants: { 'tenant-1': { featureFlags: { demo_skip_stripe: true } } },
      },
      session: readySession({ stripe: { status: '' } }),
    });

    await request(app).post('/onboarding-sessions/session-1/finalize').send({}).expect(200);

    expect(audits[1]).toEqual({
      id: 'session-1',
      event: 'finalized',
      data: { tenant_id: 'tenant-1', store_id: 'store-1', demo_skip_stripe: true },
    });
  });

  it('audits phone route finalization failures without failing finalization', async () => {
    const consoleSpy = jest.spyOn(console, 'error').mockImplementation(() => undefined);
    const upsertPhoneNumberRoute = jest.fn(async () => {
      throw new Error('route write failed');
    });
    const { app, audits } = makeHarness({ upsertPhoneNumberRoute });

    try {
      await request(app).post('/onboarding-sessions/session-1/finalize').send({}).expect(200);

      expect(audits[0]).toEqual({
        id: 'session-1',
        event: 'phone_number_route_finalize_failed',
        data: { message: 'route write failed' },
      });
      expect(audits[1]).toMatchObject({ event: 'finalized' });
    } finally {
      consoleSpy.mockRestore();
    }
  });
});
