import express from 'express';
import request from 'supertest';
import { registerVoiceNumberRoutes } from './voice_number_routes';

type TwilioHarnessConfig = {
  lookupSid?: string;
  available?: Array<{ phoneNumber: string }>;
  purchased?: { phoneNumber: string; sid: string };
};

function makeTwilio(config: TwilioHarnessConfig = {}) {
  const localList = jest.fn(async () => config.available ?? [{ phoneNumber: '+14155550123' }]);
  const create = jest.fn(async () => config.purchased ?? { phoneNumber: '+14155550123', sid: 'PNPURCHASED' });
  const lookupList = jest.fn(async () => (config.lookupSid ? [{ sid: config.lookupSid }] : []));
  const availablePhoneNumbers = jest.fn(() => ({ local: { list: localList } }));

  return {
    twilioClient: {
      availablePhoneNumbers,
      incomingPhoneNumbers: {
        create,
        list: lookupList,
      },
    },
    availablePhoneNumbers,
    create,
    localList,
    lookupList,
  };
}

function makeHarness(params: {
  session?: any;
  twilioClient?: any | null;
  twilio?: TwilioHarnessConfig;
  twilioNumberPool?: string[];
  twilioAllowPurchase?: boolean;
  elevenLabsEnabled?: boolean;
  resolveTemplateAgentId?: jest.Mock;
  importElevenLabsPhoneNumber?: jest.Mock;
  upsertPhoneNumberRoute?: jest.Mock;
  maskPhone?: jest.Mock;
} = {}) {
  const app = express();
  app.use(express.json());

  const twilio = makeTwilio(params.twilio);
  const updates: Array<{ id: string; payload: any }> = [];
  const audits: Array<{ id: string; event: string; data?: unknown }> = [];

  const sessions = {
    doc: (id: string) => ({
      update: async (payload: any) => {
        updates.push({ id, payload });
      },
    }),
  };

  const upsertPhoneNumberRoute = params.upsertPhoneNumberRoute ?? jest.fn(async () => undefined);
  const resolveTemplateAgentId = params.resolveTemplateAgentId ?? jest.fn(() => 'template-fast');
  const importElevenLabsPhoneNumber =
    params.importElevenLabsPhoneNumber ?? jest.fn(async () => 'elpn_test');
  const maskPhone = params.maskPhone ?? jest.fn((phone?: string) => (phone ? `masked:${phone}` : ''));

  registerVoiceNumberRoutes({
    app,
    sessions: sessions as any,
    twilioClient: 'twilioClient' in params ? params.twilioClient : (twilio.twilioClient as any),
    twilioNumberPool: 'twilioNumberPool' in params ? params.twilioNumberPool! : ['+15551230000'],
    twilioAllowPurchase: params.twilioAllowPurchase ?? false,
    elevenLabsEnabled: params.elevenLabsEnabled ?? false,
    resolveTemplateAgentId,
    importElevenLabsPhoneNumber,
    upsertPhoneNumberRoute,
    maskPhone,
    getSession: async (id, res) => {
      if (params.session === null) {
        res.status(404).json({ error: 'session_not_found' });
        return null;
      }
      return {
        id,
        status: 'collecting',
        business: { name: 'Demo Pizza', type: 'fast_food' },
        tenant: { tenant_id: 'tenant-1', store_id: 'store-1' },
        ...(params.session ?? {}),
      };
    },
    audit: async (id, event, data) => {
      audits.push({ id, event, data });
    },
  });

  return {
    app,
    audits,
    importElevenLabsPhoneNumber,
    maskPhone,
    resolveTemplateAgentId,
    twilio,
    updates,
    upsertPhoneNumberRoute,
  };
}

describe('voice number onboarding route', () => {
  it('requires Twilio configuration', async () => {
    const { app } = makeHarness({ twilioClient: null });

    const res = await request(app).post('/onboarding-sessions/session-1/voice-number').send({}).expect(500);

    expect(res.body.error).toBe('twilio_not_configured');
  });

  it('uses a pooled number, resolves its Twilio SID, and writes the durable route mapping', async () => {
    const { app, audits, twilio, updates, upsertPhoneNumberRoute } = makeHarness({
      twilio: { lookupSid: 'PNEXISTING' },
      twilioNumberPool: ['+15551230000'],
    });

    const res = await request(app).post('/onboarding-sessions/session-1/voice-number').send({}).expect(200);

    expect(res.body).toEqual({ number: '+15551230000', sid: 'PNEXISTING' });
    expect(twilio.lookupList).toHaveBeenCalledWith({ phoneNumber: '+15551230000', limit: 1 });
    expect(updates[0].payload.twilio).toEqual({
      number: '+15551230000',
      sid: 'PNEXISTING',
      status: 'assigned',
    });
    expect(audits[0]).toMatchObject({
      id: 'session-1',
      event: 'twilio_assigned',
      data: { number: '+15551230000', sid: 'PNEXISTING', source: 'existing' },
    });
    expect(upsertPhoneNumberRoute).toHaveBeenCalledWith({
      onboardingSessionId: 'session-1',
      toNumber: '+15551230000',
      elevenlabsPhoneNumberId: undefined,
      twilioSid: 'PNEXISTING',
      tenantId: 'tenant-1',
      storeId: 'store-1',
      businessType: 'fast_food',
      routeStatus: 'collecting',
      source: 'onboarding_voice_number',
    });
    expect(audits[1]).toMatchObject({
      event: 'phone_number_route_upserted',
      data: { to_number: 'masked:+15551230000', phone_number_id: null },
    });
  });

  it('rejects assignment when no number pool is configured and purchasing is disabled', async () => {
    const { app, audits, updates, upsertPhoneNumberRoute } = makeHarness({
      twilioNumberPool: [],
      twilioAllowPurchase: false,
    });

    const res = await request(app).post('/onboarding-sessions/session-1/voice-number').send({}).expect(400);

    expect(res.body.error).toBe('no_pool_and_purchase_disabled');
    expect(updates).toEqual([]);
    expect(audits).toEqual([]);
    expect(upsertPhoneNumberRoute).not.toHaveBeenCalled();
  });

  it('purchases a number when explicitly enabled and no pool is configured', async () => {
    const { app, audits, twilio, updates } = makeHarness({
      twilioNumberPool: [],
      twilioAllowPurchase: true,
      twilio: {
        available: [{ phoneNumber: '+14155550123' }],
        purchased: { phoneNumber: '+14155550123', sid: 'PNPURCHASED' },
      },
    });

    const res = await request(app).post('/onboarding-sessions/session-1/voice-number').send({}).expect(200);

    expect(res.body).toEqual({ number: '+14155550123', sid: 'PNPURCHASED' });
    expect(twilio.localList).toHaveBeenCalledWith({ areaCode: 415, limit: 1 });
    expect(twilio.create).toHaveBeenCalledWith({ phoneNumber: '+14155550123' });
    expect(twilio.lookupList).not.toHaveBeenCalled();
    expect(updates.map((update) => update.payload.twilio.sid)).toEqual(['PNPURCHASED', 'PNPURCHASED']);
    expect(audits[0]).toMatchObject({ event: 'twilio_assigned', data: { source: 'purchased' } });
    expect(audits[1]).toMatchObject({ event: 'twilio_assigned', data: { source: 'existing' } });
  });

  it('imports the assigned number into ElevenLabs when enabled and a template agent is available', async () => {
    const resolveTemplateAgentId = jest.fn(() => 'template-fast');
    const importElevenLabsPhoneNumber = jest.fn(async () => 'elpn_123');
    const { app, audits, updates, upsertPhoneNumberRoute } = makeHarness({
      twilio: { lookupSid: 'PNEXISTING' },
      twilioNumberPool: [],
      elevenLabsEnabled: true,
      resolveTemplateAgentId,
      importElevenLabsPhoneNumber,
    });

    const res = await request(app)
      .post('/onboarding-sessions/session-1/voice-number')
      .send({ number: '+15550001111' })
      .expect(200);

    expect(res.body).toEqual({
      number: '+15550001111',
      sid: 'PNEXISTING',
      elevenlabs_phone_number_id: 'elpn_123',
    });
    expect(resolveTemplateAgentId).toHaveBeenCalledWith('fast_food');
    expect(importElevenLabsPhoneNumber).toHaveBeenCalledWith({
      phoneNumber: '+15550001111',
      label: 'Demo Pizza (fast_food)',
      agentId: 'template-fast',
    });
    expect(updates[1].payload.twilio).toMatchObject({ elevenlabs_phone_number_id: 'elpn_123' });
    expect(audits[1]).toMatchObject({
      event: 'elevenlabs_phone_number_imported',
      data: {
        phone_number_id: 'elpn_123',
        phone_number: 'masked:+15550001111',
        agent_id: 'template-fast',
      },
    });
    expect(upsertPhoneNumberRoute).toHaveBeenCalledWith(
      expect.objectContaining({ elevenlabsPhoneNumberId: 'elpn_123' }),
    );
  });

  it('audits route mapping failures without failing the assignment response', async () => {
    const consoleSpy = jest.spyOn(console, 'error').mockImplementation(() => undefined);
    const upsertPhoneNumberRoute = jest.fn(async () => {
      throw new Error('route write failed');
    });
    const { app, audits } = makeHarness({
      twilio: { lookupSid: 'PNEXISTING' },
      upsertPhoneNumberRoute,
    });

    try {
      const res = await request(app)
        .post('/onboarding-sessions/session-1/voice-number')
        .send({ number: '+15551230000' })
        .expect(200);

      expect(res.body).toEqual({ number: '+15551230000', sid: 'PNEXISTING' });
      expect(audits[1]).toMatchObject({
        event: 'phone_number_route_upsert_failed',
        data: { message: 'route write failed' },
      });
    } finally {
      consoleSpy.mockRestore();
    }
  });
});
