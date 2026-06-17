import express, { type Express, type Response } from 'express';
import { Timestamp, type CollectionReference, type Firestore } from '@google-cloud/firestore';
import type Stripe from 'stripe';

type StripeSession = {
  stripe?: {
    account_id?: string;
  };
};

type FetchLike = (url: string) => Promise<{
  ok: boolean;
  json: () => Promise<any>;
}>;

type RegisterStripeConnectRoutesParams = {
  app: Express;
  firestore: Firestore;
  sessions: CollectionReference;
  stripe: Stripe | null;
  stripeWebhookSecret: string;
  mapsKey: string;
  fetchImpl: FetchLike;
  getSession: (id: string, res: Response) => Promise<(StripeSession & { id: string }) | null>;
  audit: (id: string, event: string, data?: unknown) => Promise<void>;
  upsertDeliveryPartnerStripeFromAccount: (firestore: Firestore, account: Stripe.Account) => Promise<void>;
};

export function registerStripeConnectRoutes(params: RegisterStripeConnectRoutesParams): void {
  params.app.post('/stripe/account', async (req, res) => {
    if (!params.stripe) return res.status(500).json({ error: 'stripe_not_configured' });
    try {
      const { session_id, capabilities = ['card_payments', 'transfers'], business_type = 'company' } = req.body || {};
      if (!session_id) return res.status(400).json({ error: 'session_id_required' });

      const session = await params.getSession(session_id, res);
      if (!session) return;

      const account = await params.stripe.accounts.create({
        type: 'custom',
        country: 'US',
        business_type,
        capabilities: Object.fromEntries(capabilities.map((capability: string) => [capability, { requested: true }])),
        settings: { payouts: { schedule: { interval: 'manual' } } },
      });

      await params.sessions.doc(session_id).update({
        stripe: {
          account_id: account.id,
          status: account.requirements?.disabled_reason ?? 'pending',
          capabilities: account.capabilities ?? {},
        },
        updated_at: Timestamp.now(),
      });
      await params.audit(session_id, 'stripe_account_created', { account_id: account.id });
      return res.status(201).json({ account_id: account.id, capabilities });
    } catch (err: any) {
      console.error('stripe account error', err);
      return res.status(500).json({ error: 'stripe_account_failed', message: err.message });
    }
  });

  params.app.post('/stripe/account-session', async (req, res) => {
    if (!params.stripe) return res.status(500).json({ error: 'stripe_not_configured' });
    try {
      const { session_id } = req.body || {};
      if (!session_id) return res.status(400).json({ error: 'session_id_required' });

      const sessionDoc = await params.getSession(session_id, res);
      if (!sessionDoc) return;

      const accountId = sessionDoc.stripe?.account_id;
      if (!accountId) return res.status(400).json({ error: 'account_id_missing_for_session' });

      const stripeSession = await params.stripe.accountSessions.create({
        account: accountId,
        components: {
          account_onboarding: { enabled: true },
          payouts: { enabled: true },
        },
      });
      return res.status(201).json({ client_secret: stripeSession.client_secret });
    } catch (err: any) {
      console.error('stripe account-session error', err);
      return res.status(500).json({ error: 'stripe_account_session_failed', message: err.message });
    }
  });

  params.app.post('/stripe/webhook', express.raw({ type: 'application/json' }), async (req, res) => {
    if (!params.stripe) return res.status(500).send('stripe_not_configured');
    if (!params.stripeWebhookSecret) return res.status(500).send('webhook_secret_not_configured');

    const sig = req.headers['stripe-signature'];
    if (!sig) return res.status(400).send('missing_signature');

    try {
      const event = params.stripe.webhooks.constructEvent(req.body, sig as string, params.stripeWebhookSecret);
      if (event.type === 'account.updated' || event.type.startsWith('capability.')) {
        const account = event.data.object as Stripe.Account;
        await handleStripeAccountEvent(params, account, event.type);
      }
      console.log('stripe event', event.type);
      return res.json({ received: true, verified: true });
    } catch (err: any) {
      console.error('stripe webhook error', err.message);
      return res.status(400).send(`Webhook Error: ${err.message}`);
    }
  });
}

async function handleStripeAccountEvent(
  params: RegisterStripeConnectRoutesParams,
  account: Stripe.Account,
  eventType: string,
): Promise<void> {
  const qsnap = await params.sessions.where('stripe.account_id', '==', account.id).limit(1).get();
  if (!qsnap.empty) {
    const doc = qsnap.docs[0];
    const sessionId = doc.id;
    const status = account.requirements?.disabled_reason ?? 'active';
    const enrichment = await resolveStripeBusinessEnrichment(params, account);

    const updates: any = {
      stripe: {
        account_id: account.id,
        status,
        capabilities: account.capabilities ?? {},
      },
      updated_at: Timestamp.now(),
    };

    if (enrichment.hasBusinessUpdates) {
      updates.business = {
        ...(doc.data().business ?? {}),
        ...enrichment.business,
      };
    }

    await doc.ref.update(updates);
    await params.audit(sessionId, 'stripe_event', {
      type: eventType,
      status,
      enriched: Boolean(enrichment.timezone),
    });
  }

  try {
    await params.upsertDeliveryPartnerStripeFromAccount(params.firestore, account);
  } catch (err) {
    console.error('delivery partner stripe webhook update failed', err);
  }
}

async function resolveStripeBusinessEnrichment(
  params: RegisterStripeConnectRoutesParams,
  account: Stripe.Account,
): Promise<{ business: Record<string, unknown>; hasBusinessUpdates: boolean; timezone?: string }> {
  const businessAddress =
    account.company?.address?.line1 ||
    account.business_profile?.support_address?.line1 ||
    account.business_profile?.url ||
    '';
  const country = account.company?.address?.country || account.business_profile?.support_address?.country;
  const phone = account.business_profile?.support_phone || account.company?.phone;
  const name = account.business_profile?.name || account.company?.name;

  let tz: any = {};
  try {
    tz = await geocodeTimezone(params.mapsKey, params.fetchImpl, businessAddress, country || undefined);
  } catch (err) {
    console.error('geocode error', err);
  }

  const business = {
    ...(name ? { name } : {}),
    ...(phone ? { phone } : {}),
    ...(businessAddress ? { address: businessAddress } : {}),
    ...(country ? { country } : {}),
    ...(tz.timezone ? { timezone: tz.timezone } : {}),
    ...(tz.lat ? { lat: tz.lat, lng: tz.lng } : {}),
  };
  return {
    business,
    hasBusinessUpdates: Boolean(name || phone || businessAddress || country || tz.timezone),
    timezone: tz.timezone,
  };
}

async function geocodeTimezone(
  mapsKey: string,
  fetchImpl: FetchLike,
  address?: string,
  country?: string,
): Promise<Record<string, unknown>> {
  if (!address || !mapsKey) return {};
  const encoded = encodeURIComponent(address + (country ? ` ${country}` : ''));
  const geoUrl = `https://maps.googleapis.com/maps/api/geocode/json?address=${encoded}&key=${mapsKey}`;
  const geoResp = await fetchImpl(geoUrl);
  if (!geoResp.ok) return {};
  const geo: any = await geoResp.json();
  const result = geo.results?.[0];
  if (!result) return {};

  const loc = result.geometry?.location;
  const lat = loc?.lat;
  const lng = loc?.lng;
  if (lat == null || lng == null) return { address: result.formatted_address };

  const tzUrl = `https://maps.googleapis.com/maps/api/timezone/json?location=${lat},${lng}&timestamp=${Math.floor(
    Date.now() / 1000,
  )}&key=${mapsKey}`;
  const tzResp = await fetchImpl(tzUrl);
  let timezone: string | undefined;
  if (tzResp.ok) {
    const tz: any = await tzResp.json();
    if (tz.status === 'OK') timezone = tz.timeZoneId;
  }
  return {
    address: result.formatted_address as string,
    lat,
    lng,
    timezone,
  };
}
