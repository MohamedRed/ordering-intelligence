import express from 'express';
import request from 'supertest';
import { registerStripeConnectRoutes } from './stripe_connect_routes';

function makeStripe(params: { event?: any; account?: any; accountSession?: any } = {}) {
  return {
    accounts: {
      create: jest.fn(async () => params.account ?? { id: 'acct_123', requirements: {}, capabilities: {} }),
    },
    accountSessions: {
      create: jest.fn(async () => params.accountSession ?? { client_secret: 'secret_123' }),
    },
    webhooks: {
      constructEvent: jest.fn(() => params.event ?? { type: 'account.updated', data: { object: { id: 'acct_123' } } }),
    },
  };
}

function makeHarness(params: {
  session?: any;
  stripe?: any | null;
  stripeWebhookSecret?: string;
  fetchImpl?: jest.Mock;
  event?: any;
  webhookSession?: { id: string; data: any };
  upsertDeliveryPartnerStripeFromAccount?: jest.Mock;
} = {}) {
  const app = express();
  app.use((req, res, next) => {
    if (req.path === '/stripe/webhook') return next();
    return express.json()(req, res, next);
  });

  const updates: Array<{ id: string; payload: any }> = [];
  const webhookUpdates: Array<{ id: string; payload: any }> = [];
  const audits: Array<{ id: string; event: string; data?: unknown }> = [];
  const whereCalls: Array<{ field: string; op: string; value: unknown }> = [];
  const stripe = 'stripe' in params ? params.stripe : makeStripe({ event: params.event });
  const fetchImpl = params.fetchImpl ?? jest.fn(async () => ({ ok: false, json: async () => ({}) }));
  const upsertDeliveryPartnerStripeFromAccount =
    params.upsertDeliveryPartnerStripeFromAccount ?? jest.fn(async () => undefined);

  const sessions = {
    doc: (id: string) => ({
      update: async (payload: any) => {
        updates.push({ id, payload });
      },
    }),
    where: (field: string, op: string, value: unknown) => {
      whereCalls.push({ field, op, value });
      return {
        limit: () => ({
          get: async () => ({
            empty: !params.webhookSession,
            docs: params.webhookSession
              ? [
                  {
                    id: params.webhookSession.id,
                    data: () => params.webhookSession?.data,
                    ref: {
                      update: async (payload: any) => {
                        webhookUpdates.push({ id: params.webhookSession!.id, payload });
                      },
                    },
                  },
                ]
              : [],
          }),
        }),
      };
    },
  };

  registerStripeConnectRoutes({
    app,
    firestore: {} as any,
    sessions: sessions as any,
    stripe: stripe as any,
    stripeWebhookSecret: params.stripeWebhookSecret ?? 'whsec_test',
    mapsKey: 'maps-key',
    fetchImpl,
    upsertDeliveryPartnerStripeFromAccount,
    getSession: async (id, res) => {
      if (params.session === null) {
        res.status(404).json({ error: 'session_not_found' });
        return null;
      }
      return { id, ...(params.session ?? { stripe: { account_id: 'acct_123' } }) };
    },
    audit: async (id, event, data) => {
      audits.push({ id, event, data });
    },
  });

  return {
    app,
    audits,
    fetchImpl,
    stripe,
    updates,
    upsertDeliveryPartnerStripeFromAccount,
    webhookUpdates,
    whereCalls,
  };
}

describe('Stripe Connect onboarding routes', () => {
  it('creates a custom Stripe account and stores it on the onboarding session', async () => {
    const stripe = makeStripe({
      account: {
        id: 'acct_new',
        requirements: { disabled_reason: 'requirements.pending' },
        capabilities: { card_payments: 'pending' },
      },
    });
    const { app, audits, updates } = makeHarness({ stripe });

    const res = await request(app)
      .post('/stripe/account')
      .send({ session_id: 'session-1', capabilities: ['card_payments'], business_type: 'individual' })
      .expect(201);

    expect(res.body).toEqual({ account_id: 'acct_new', capabilities: ['card_payments'] });
    expect(stripe.accounts.create).toHaveBeenCalledWith(
      expect.objectContaining({
        type: 'custom',
        country: 'US',
        business_type: 'individual',
        capabilities: { card_payments: { requested: true } },
      }),
    );
    expect(updates[0].payload.stripe).toEqual({
      account_id: 'acct_new',
      status: 'requirements.pending',
      capabilities: { card_payments: 'pending' },
    });
    expect(audits).toEqual([{ id: 'session-1', event: 'stripe_account_created', data: { account_id: 'acct_new' } }]);
  });

  it('creates embedded account sessions and rejects missing session account ids', async () => {
    const { app, stripe } = makeHarness();

    const res = await request(app).post('/stripe/account-session').send({ session_id: 'session-1' }).expect(201);
    expect(res.body).toEqual({ client_secret: 'secret_123' });
    expect(stripe.accountSessions.create).toHaveBeenCalledWith({
      account: 'acct_123',
      components: {
        account_onboarding: { enabled: true },
        payouts: { enabled: true },
      },
    });

    const missing = await request(makeHarness({ session: { stripe: {} } }).app)
      .post('/stripe/account-session')
      .send({ session_id: 'session-1' })
      .expect(400);
    expect(missing.body.error).toBe('account_id_missing_for_session');
  });

  it('requires Stripe and webhook signature configuration', async () => {
    const noStripe = await request(makeHarness({ stripe: null }).app).post('/stripe/account').send({}).expect(500);
    expect(noStripe.body.error).toBe('stripe_not_configured');

    await request(makeHarness({ stripeWebhookSecret: '' }).app)
      .post('/stripe/webhook')
      .set('stripe-signature', 'sig_test')
      .set('Content-Type', 'application/json')
      .send(Buffer.from('{}'))
      .expect(500, 'webhook_secret_not_configured');

    await request(makeHarness().app)
      .post('/stripe/webhook')
      .set('Content-Type', 'application/json')
      .send(Buffer.from('{}'))
      .expect(400, 'missing_signature');
  });

  it('handles account update webhooks, enriches business data, and syncs delivery partner Stripe state', async () => {
    const account = {
      id: 'acct_webhook',
      requirements: {},
      capabilities: { transfers: 'active' },
      company: {
        name: 'Demo LLC',
        phone: '+15551230000',
        address: { line1: '123 Main St', country: 'US' },
      },
      business_profile: {},
    };
    const event = { type: 'account.updated', data: { object: account } };
    const fetchImpl = jest
      .fn()
      .mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          results: [{ formatted_address: '123 Main St, Testville', geometry: { location: { lat: 1, lng: 2 } } }],
        }),
      })
      .mockResolvedValueOnce({ ok: true, json: async () => ({ status: 'OK', timeZoneId: 'America/Los_Angeles' }) });
    const {
      app,
      audits,
      stripe,
      upsertDeliveryPartnerStripeFromAccount,
      webhookUpdates,
      whereCalls,
    } = makeHarness({
      event,
      fetchImpl,
      webhookSession: { id: 'session-1', data: { business: { existing: true } } },
    });

    const res = await request(app)
      .post('/stripe/webhook')
      .set('stripe-signature', 'sig_test')
      .set('Content-Type', 'application/json')
      .send(Buffer.from('{}'))
      .expect(200);

    expect(res.body).toEqual({ received: true, verified: true });
    expect(stripe.webhooks.constructEvent).toHaveBeenCalledWith(expect.any(Buffer), 'sig_test', 'whsec_test');
    expect(whereCalls).toEqual([{ field: 'stripe.account_id', op: '==', value: 'acct_webhook' }]);
    expect(webhookUpdates[0].payload.stripe).toEqual({
      account_id: 'acct_webhook',
      status: 'active',
      capabilities: { transfers: 'active' },
    });
    expect(webhookUpdates[0].payload.business).toMatchObject({
      existing: true,
      name: 'Demo LLC',
      phone: '+15551230000',
      address: '123 Main St',
      country: 'US',
      timezone: 'America/Los_Angeles',
      lat: 1,
      lng: 2,
    });
    expect(audits).toEqual([
      {
        id: 'session-1',
        event: 'stripe_event',
        data: { type: 'account.updated', status: 'active', enriched: true },
      },
    ]);
    expect(upsertDeliveryPartnerStripeFromAccount).toHaveBeenCalledWith({}, account);
  });
});
