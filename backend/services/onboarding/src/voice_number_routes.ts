import type { Express, Response } from 'express';
import { Timestamp, type CollectionReference } from '@google-cloud/firestore';

type VoiceNumberSession = {
  status?: string;
  business?: {
    name?: string;
    type?: string;
  };
  agent?: {
    template_agent_id?: string;
  };
  tenant?: {
    tenant_id?: string;
    store_id?: string;
  };
};

type TwilioPhoneNumber = {
  phoneNumber?: string;
  sid?: string;
};

type VoiceNumberTwilioClient = {
  availablePhoneNumbers: (countryCode: string) => {
    local: {
      list: (params: { areaCode: number; limit: number }) => Promise<TwilioPhoneNumber[]>;
    };
  };
  incomingPhoneNumbers: {
    create: (params: { phoneNumber: string }) => Promise<TwilioPhoneNumber>;
    list: (params: { phoneNumber: string | undefined; limit: number }) => Promise<TwilioPhoneNumber[]>;
  };
};

type ImportElevenLabsPhoneNumber = (params: {
  phoneNumber: string;
  label: string;
  agentId: string;
}) => Promise<string>;

type UpsertPhoneNumberRoute = (params: {
  onboardingSessionId: string;
  toNumber?: string;
  elevenlabsPhoneNumberId?: string;
  twilioSid?: string;
  tenantId?: string;
  storeId?: string;
  businessType?: string;
  routeStatus?: string;
  source: 'onboarding_voice_number' | 'onboarding_finalize' | 'manual';
}) => Promise<void>;

type RegisterVoiceNumberRoutesParams = {
  app: Express;
  sessions: CollectionReference;
  twilioClient: VoiceNumberTwilioClient | null;
  twilioNumberPool: string[];
  twilioAllowPurchase: boolean;
  elevenLabsEnabled: boolean;
  resolveTemplateAgentId: (businessTypeRaw: string) => string;
  importElevenLabsPhoneNumber: ImportElevenLabsPhoneNumber;
  upsertPhoneNumberRoute: UpsertPhoneNumberRoute;
  maskPhone: (phone: string | undefined) => string;
  getSession: (id: string, res: Response) => Promise<(VoiceNumberSession & { id: string }) | null>;
  audit: (id: string, event: string, data?: unknown) => Promise<void>;
};

export function registerVoiceNumberRoutes(params: RegisterVoiceNumberRoutesParams): void {
  params.app.post('/onboarding-sessions/:id/voice-number', async (req, res) => {
    try {
      const { id } = req.params;
      const snap = await params.getSession(id, res);
      if (!snap) return;

      if (!params.twilioClient) return res.status(500).json({ error: 'twilio_not_configured' });

      let number = req.body?.number as string | undefined;
      let twilioSid: string | undefined;

      if (!number) {
        const assigned = await assignNumberFromPoolOrPurchase(params, id, res);
        if ('response' in assigned) return assigned.response;
        number = assigned.number;
        twilioSid = assigned.twilioSid;
      }

      twilioSid = await resolveTwilioSid(params.twilioClient, number, twilioSid);
      await storeTwilioAssignment(params, id, number, twilioSid);

      const elevenLabsPhoneNumberId = await maybeImportElevenLabsPhoneNumber(params, id, snap, number, twilioSid);
      await upsertDurablePhoneRoute(params, id, snap, number, twilioSid, elevenLabsPhoneNumberId);

      return res.json({ number, sid: twilioSid, elevenlabs_phone_number_id: elevenLabsPhoneNumberId });
    } catch (err: any) {
      console.error('voice-number error', err);
      return res.status(500).json({ error: 'voice_number_failed', message: err.message });
    }
  });
}

async function assignNumberFromPoolOrPurchase(
  params: RegisterVoiceNumberRoutesParams,
  sessionId: string,
  res: Response,
): Promise<{ number: string; twilioSid?: string } | { response: Response }> {
  if (params.twilioNumberPool.length > 0) {
    return { number: params.twilioNumberPool[0] };
  }

  if (!params.twilioAllowPurchase) {
    return { response: res.status(400).json({ error: 'no_pool_and_purchase_disabled' }) };
  }

  const search = await params.twilioClient!.availablePhoneNumbers('US').local.list({ areaCode: 415, limit: 1 });
  if (!search.length || !search[0].phoneNumber) {
    return { response: res.status(500).json({ error: 'no_numbers_available' }) };
  }

  const purchased = await params.twilioClient!.incomingPhoneNumbers.create({ phoneNumber: search[0].phoneNumber });
  const number = purchased.phoneNumber;
  if (!number) throw new Error('twilio_purchase_missing_number');

  await params.sessions.doc(sessionId).update({
    twilio: { number, sid: purchased.sid, status: 'assigned' },
    updated_at: Timestamp.now(),
  });
  await params.audit(sessionId, 'twilio_assigned', { number, sid: purchased.sid, source: 'purchased' });

  return { number, twilioSid: purchased.sid };
}

async function resolveTwilioSid(
  twilioClient: VoiceNumberTwilioClient,
  number: string | undefined,
  existingSid: string | undefined,
): Promise<string | undefined> {
  if (existingSid) return existingSid;
  const lookup = await twilioClient.incomingPhoneNumbers.list({ phoneNumber: number, limit: 1 });
  return lookup[0]?.sid;
}

async function storeTwilioAssignment(
  params: RegisterVoiceNumberRoutesParams,
  sessionId: string,
  number: string | undefined,
  twilioSid: string | undefined,
): Promise<void> {
  await params.sessions.doc(sessionId).update({
    twilio: { number, sid: twilioSid, status: 'assigned' },
    updated_at: Timestamp.now(),
  });
  await params.audit(sessionId, 'twilio_assigned', {
    number,
    sid: twilioSid,
    source: twilioSid ? 'existing' : 'pool_without_sid',
  });
}

async function maybeImportElevenLabsPhoneNumber(
  params: RegisterVoiceNumberRoutesParams,
  sessionId: string,
  session: VoiceNumberSession,
  number: string | undefined,
  twilioSid: string | undefined,
): Promise<string | undefined> {
  if (!params.elevenLabsEnabled || !number) return undefined;

  try {
    const businessType = ((session.business?.type || '').trim() || 'fast_food').toLowerCase();
    const agentId =
      (session.agent?.template_agent_id || '').trim() || params.resolveTemplateAgentId(businessType);
    if (!agentId) return undefined;

    const label = `${(session.business?.name || 'Business').slice(0, 40)} (${businessType})`;
    const elevenLabsPhoneNumberId = await params.importElevenLabsPhoneNumber({
      phoneNumber: number,
      label,
      agentId,
    });

    await params.sessions.doc(sessionId).update({
      twilio: {
        number,
        sid: twilioSid,
        status: 'assigned',
        elevenlabs_phone_number_id: elevenLabsPhoneNumberId,
      },
      updated_at: Timestamp.now(),
    });
    await params.audit(sessionId, 'elevenlabs_phone_number_imported', {
      phone_number_id: elevenLabsPhoneNumberId,
      phone_number: params.maskPhone(number),
      agent_id: agentId,
    });
    return elevenLabsPhoneNumberId;
  } catch (err: any) {
    console.error('elevenlabs phone import failed', err?.message ?? err);
    await params.audit(sessionId, 'elevenlabs_phone_number_import_failed', {
      message: err?.message ?? String(err),
    });
    return undefined;
  }
}

async function upsertDurablePhoneRoute(
  params: RegisterVoiceNumberRoutesParams,
  sessionId: string,
  session: VoiceNumberSession,
  number: string | undefined,
  twilioSid: string | undefined,
  elevenLabsPhoneNumberId: string | undefined,
): Promise<void> {
  try {
    await params.upsertPhoneNumberRoute({
      onboardingSessionId: sessionId,
      toNumber: number,
      elevenlabsPhoneNumberId: elevenLabsPhoneNumberId,
      twilioSid,
      tenantId: session.tenant?.tenant_id || '',
      storeId: session.tenant?.store_id || '',
      businessType: session.business?.type || '',
      routeStatus: session.status || 'active',
      source: 'onboarding_voice_number',
    });
    await params.audit(sessionId, 'phone_number_route_upserted', {
      to_number: params.maskPhone(number),
      phone_number_id: elevenLabsPhoneNumberId || null,
    });
  } catch (err: any) {
    console.error('phone_number_routes upsert failed', err?.message ?? err);
    await params.audit(sessionId, 'phone_number_route_upsert_failed', { message: err?.message ?? String(err) });
  }
}
