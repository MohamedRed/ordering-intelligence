import type { Express, Response } from 'express';
import { FieldValue, Timestamp, type CollectionReference, type Firestore } from '@google-cloud/firestore';
import { buildDefaultOrderComms } from './finalize_order_comms.js';

type FinalizeSession = {
  business?: {
    name?: string;
    address?: string;
    phone?: string;
    timezone?: string;
    type?: string;
    currency?: string;
    fuel_default_prepay_cents?: number;
    fuelDefaultPrepayCents?: number;
  };
  flyers?: string[];
  stripe?: {
    account_id?: string;
    status?: string;
  };
  twilio?: {
    number?: string;
    sid?: string;
    elevenlabs_phone_number_id?: string;
  };
  ingestion?: {
    job_ids?: string[];
    status?: string;
  };
  agent?: {
    template_agent_id?: string;
    agent_id?: string;
    voice_id?: string;
    branch_id?: string;
  };
  tenant?: {
    tenant_id?: string;
    store_id?: string;
  };
};

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

type RegisterFinalizeRoutesParams = {
  app: Express;
  firestore: Firestore;
  sessions: CollectionReference;
  onboardingTenants: CollectionReference;
  allowDemoSkipStripe: boolean;
  demoSkipStripeFlag: string;
  getSession: (id: string, res: Response) => Promise<(FinalizeSession & { id: string }) | null>;
  audit: (id: string, event: string, data?: unknown) => Promise<void>;
  upsertPhoneNumberRoute: UpsertPhoneNumberRoute;
  maskPhone: (phone: string | undefined) => string;
};

export function registerFinalizeRoutes(params: RegisterFinalizeRoutesParams): void {
  params.app.post('/onboarding-sessions/:id/finalize', async (req, res) => {
    try {
      const { id } = req.params;
      const snap = await params.getSession(id, res);
      if (!snap) return;

      const demoSkipStripe = await resolveDemoSkipStripe(params, snap);
      const missing = resolveMissingFinalizeFields(snap, demoSkipStripe);
      if (missing.length) return res.status(400).json({ error: 'not_ready', missing });

      const tenantId = snap.tenant?.tenant_id || `tenant_${id}`;
      const storeId = snap.tenant?.store_id || `store_${id}`;
      const ts = Timestamp.now();

      await params.firestore.collection('tenants').doc(tenantId).set(buildTenantPayload(snap, ts), { merge: true });
      await params.firestore.collection('stores').doc(storeId).set(buildStorePayload(snap, tenantId, storeId, ts), {
        merge: true,
      });

      await finalizePhoneRoute(params, id, snap, tenantId, storeId);

      await params.sessions.doc(id).update({
        status: 'ready',
        tenant: { tenant_id: tenantId, store_id: storeId },
        updated_at: ts,
      });
      const auditPayload: Record<string, unknown> = { tenant_id: tenantId, store_id: storeId };
      if (demoSkipStripe) auditPayload.demo_skip_stripe = true;
      await params.audit(id, 'finalized', auditPayload);

      if (tenantId) {
        await params.onboardingTenants.doc(tenantId).set(
          {
            active_session_id: FieldValue.delete(),
            last_session_id: id,
            store_id: storeId,
            updated_at: ts,
          } as any,
          { merge: true },
        );
      }

      return res.json({ status: 'ready', tenant_id: tenantId, store_id: storeId });
    } catch (err: any) {
      console.error('finalize error', err);
      return res.status(500).json({ error: 'finalize_failed', message: err.message });
    }
  });
}

async function resolveDemoSkipStripe(
  params: RegisterFinalizeRoutesParams,
  session: FinalizeSession,
): Promise<boolean> {
  const tenantIdForFlags = (session.tenant?.tenant_id || '').trim();
  if (!params.allowDemoSkipStripe || !tenantIdForFlags) return false;

  try {
    const tenantSnap = await params.firestore.collection('tenants').doc(tenantIdForFlags).get();
    const flags = (tenantSnap.data() as any)?.featureFlags as Record<string, any> | undefined;
    return flags?.[params.demoSkipStripeFlag] === true;
  } catch (err) {
    console.warn('demo_skip_stripe flag read failed', err);
    return false;
  }
}

function resolveMissingFinalizeFields(session: FinalizeSession, demoSkipStripe: boolean): string[] {
  const missing: string[] = [];
  if (!session.business?.name) missing.push('business.name');
  if (!session.flyers || session.flyers.length === 0) missing.push('flyers');
  if (!session.twilio?.number) missing.push('twilio.number');
  const stripeStatus = session.stripe?.status || '';
  if (!demoSkipStripe && !['active', 'pending_review', 'requirements_due', 'pending'].includes(stripeStatus)) {
    missing.push('stripe_kyc');
  }
  const ingestStatus = session.ingestion?.status || '';
  if (!['succeeded', 'partial_ok'].includes(ingestStatus)) missing.push('ingestion');
  if (!session.agent?.template_agent_id && !session.agent?.agent_id) missing.push('agent');
  return missing;
}

function buildTenantPayload(session: FinalizeSession, ts: Timestamp) {
  return {
    name: session.business?.name || 'Unnamed',
    phone: session.business?.phone || '',
    address: session.business?.address || '',
    timezone: session.business?.timezone || '',
    stripe_account_id: session.stripe?.account_id || '',
    status: 'ready',
    created_at: ts,
    updated_at: ts,
  };
}

function buildStorePayload(
  session: FinalizeSession,
  tenantId: string,
  storeId: string,
  ts: Timestamp,
) {
  return {
    store_id: storeId,
    tenant_id: tenantId,
    business_type: session.business?.type || '',
    currency: session.business?.currency || '',
    fuel_default_prepay_cents:
      session.business?.fuel_default_prepay_cents || session.business?.fuelDefaultPrepayCents || 0,
    menu_job_ids: session.ingestion?.job_ids || [],
    elevenlabs_agent_template_id: session.agent?.template_agent_id || '',
    elevenlabs_agent_mode: session.agent?.template_agent_id ? 'shared_template' : session.agent?.agent_id ? 'per_tenant' : '',
    ...(session.agent?.agent_id ? { elevenlabs_agent_id: session.agent?.agent_id || '' } : {}),
    elevenlabs_voice_id: session.agent?.voice_id || '',
    elevenlabs_agent_branch_id: session.agent?.branch_id || '',
    elevenlabs_variables: {
      tenantId,
      storeId,
      businessType: (session.business?.type || '').trim(),
    },
    twilio_number: session.twilio?.number || '',
    elevenlabs_phone_number_id: session.twilio?.elevenlabs_phone_number_id || '',
    order_comms: buildDefaultOrderComms(),
    created_at: ts,
    updated_at: ts,
  };
}

async function finalizePhoneRoute(
  params: RegisterFinalizeRoutesParams,
  sessionId: string,
  session: FinalizeSession,
  tenantId: string,
  storeId: string,
): Promise<void> {
  try {
    await params.upsertPhoneNumberRoute({
      onboardingSessionId: sessionId,
      toNumber: session.twilio?.number || '',
      elevenlabsPhoneNumberId: session.twilio?.elevenlabs_phone_number_id || '',
      twilioSid: session.twilio?.sid || '',
      tenantId,
      storeId,
      businessType: session.business?.type || '',
      routeStatus: 'ready',
      source: 'onboarding_finalize',
    });
    await params.audit(sessionId, 'phone_number_route_finalized', {
      tenant_id: tenantId,
      store_id: storeId,
      to_number: params.maskPhone(session.twilio?.number || ''),
    });
  } catch (err: any) {
    console.error('phone_number_routes finalize upsert failed', err?.message ?? err);
    await params.audit(sessionId, 'phone_number_route_finalize_failed', { message: err?.message ?? String(err) });
  }
}
