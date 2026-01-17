import type express from 'express';
import type Stripe from 'stripe';
import { FieldValue, Firestore, Timestamp } from '@google-cloud/firestore';
import { v4 as uuidv4 } from 'uuid';
import { buildStripeEmbedHtml } from './stripe_embed.js';

const DELIVERY_PARTNER_STRIPE = 'delivery_partner_stripe';
const DELIVERY_PARTNER_STRIPE_SESSIONS = 'delivery_partner_stripe_sessions';
const MARKETPLACE_DELIVERERS = 'marketplace_deliverers';
const EMBED_SESSION_TTL_MINUTES = 30;

type StripeRequirements = {
  currently_due: string[];
  eventually_due: string[];
  past_due: string[];
  pending_verification: string[];
  disabled_reason: string;
};

type StripeStatusPayload = {
  account_id: string;
  status: string;
  payouts_enabled: boolean;
  charges_enabled: boolean;
  details_submitted: boolean;
  capabilities: Stripe.Account.Capabilities | null;
  requirements: StripeRequirements;
};

type StripeStatusDoc = {
  deliverer_id: string;
  stripe: StripeStatusPayload;
  updated_at: FirebaseFirestore.Timestamp;
  created_at?: FirebaseFirestore.Timestamp;
  audit?: Array<{ ts: FirebaseFirestore.Timestamp; actor: string; event: string; data?: any }>;
};

type DeliveryPartnerStripeSession = {
  deliverer_id: string;
  account_id: string;
  created_at: FirebaseFirestore.Timestamp;
  expires_at: FirebaseFirestore.Timestamp;
  updated_at?: FirebaseFirestore.Timestamp;
};

type DeliveryPartnerStripeDeps = {
  app: express.Express;
  firestore: Firestore;
  stripe: Stripe | null;
  publicBaseUrl?: string;
  stripePublishableKey?: string;
};

const normalizeDelivererId = (value: unknown): string => {
  if (typeof value !== 'string') return '';
  return value.trim();
};

const buildStripeRequirements = (account: Stripe.Account): StripeRequirements => ({
  currently_due: account.requirements?.currently_due ?? [],
  eventually_due: account.requirements?.eventually_due ?? [],
  past_due: account.requirements?.past_due ?? [],
  pending_verification: account.requirements?.pending_verification ?? [],
  disabled_reason: account.requirements?.disabled_reason ?? '',
});

const buildStripeStatus = (account: Stripe.Account): StripeStatusPayload => {
  const requirements = buildStripeRequirements(account);
  const status = requirements.disabled_reason
    ? requirements.disabled_reason
    : account.payouts_enabled && account.details_submitted
      ? 'active'
      : 'pending';
  return {
    account_id: account.id,
    status,
    payouts_enabled: account.payouts_enabled ?? false,
    charges_enabled: account.charges_enabled ?? false,
    details_submitted: account.details_submitted ?? false,
    capabilities: account.capabilities ?? null,
    requirements,
  };
};

const appendAudit = async (
  docRef: FirebaseFirestore.DocumentReference,
  event: string,
  data?: any,
) => {
  const ts = Timestamp.now();
  const entry: any = { ts, actor: 'system', event };
  if (data !== undefined) entry.data = data;
  await docRef.set({
    audit: FieldValue.arrayUnion(entry),
    updated_at: ts,
  }, { merge: true });
};

const ensureDelivererExists = async (
  firestore: Firestore,
  delivererId: string,
): Promise<boolean> => {
  const snap = await firestore.collection(MARKETPLACE_DELIVERERS).doc(delivererId).get();
  return snap.exists;
};

const upsertStripeDoc = async (
  firestore: Firestore,
  delivererId: string,
  stripePayload: StripeStatusPayload,
  event: string,
  eventData?: any,
): Promise<void> => {
  const ref = firestore.collection(DELIVERY_PARTNER_STRIPE).doc(delivererId);
  const ts = Timestamp.now();
  const snap = await ref.get();
  const base: Partial<StripeStatusDoc> = snap.exists
    ? {}
    : { deliverer_id: delivererId, created_at: ts };
  await ref.set(
    {
      ...base,
      stripe: stripePayload,
      updated_at: ts,
    },
    { merge: true },
  );
  await appendAudit(ref, event, eventData);
};

const isExpired = (ts?: FirebaseFirestore.Timestamp | null): boolean => {
  if (!ts) return true;
  return ts.toDate().getTime() <= Date.now();
};

const baseUrlFromRequest = (req: express.Request, publicBaseUrl?: string): string => {
  if (publicBaseUrl && publicBaseUrl.trim().length > 0) {
    return publicBaseUrl.replace(/\/$/, '');
  }
  const proto = (req.headers['x-forwarded-proto'] || req.protocol || 'https') as string;
  const host = (req.headers['x-forwarded-host'] || req.headers['host'] || '').toString();
  return `${proto}://${host}`.replace(/\/$/, '');
};


export const upsertDeliveryPartnerStripeFromAccount = async (
  firestore: Firestore,
  account: Stripe.Account,
): Promise<void> => {
  const qsnap = await firestore
    .collection(DELIVERY_PARTNER_STRIPE)
    .where('stripe.account_id', '==', account.id)
    .limit(1)
    .get();
  if (qsnap.empty) return;
  const ref = qsnap.docs[0].ref;
  const delivererId = qsnap.docs[0].id;
  const payload = buildStripeStatus(account);
  await ref.set(
    {
      stripe: payload,
      updated_at: Timestamp.now(),
    },
    { merge: true },
  );
  await appendAudit(ref, 'stripe_event', {
    type: 'account.updated',
    status: payload.status,
    deliverer_id: delivererId,
  });
};

const createEmbeddedSession = async (params: {
  firestore: Firestore;
  delivererId: string;
  accountId: string;
}): Promise<string> => {
  const token = uuidv4();
  const now = Timestamp.now();
  const expiresAt = Timestamp.fromDate(
    new Date(Date.now() + EMBED_SESSION_TTL_MINUTES * 60 * 1000),
  );
  const payload: DeliveryPartnerStripeSession = {
    deliverer_id: params.delivererId,
    account_id: params.accountId,
    created_at: now,
    expires_at: expiresAt,
  };
  await params.firestore
    .collection(DELIVERY_PARTNER_STRIPE_SESSIONS)
    .doc(token)
    .set(payload);
  return token;
};

const fetchSessionDoc = async (
  firestore: Firestore,
  token: string,
): Promise<FirebaseFirestore.DocumentSnapshot | null> => {
  const doc = await firestore.collection(DELIVERY_PARTNER_STRIPE_SESSIONS).doc(token).get();
  if (!doc.exists) return null;
  return doc;
};

export const registerDeliveryPartnerStripeRoutes = ({
  app,
  firestore,
  stripe,
  publicBaseUrl,
  stripePublishableKey,
}: DeliveryPartnerStripeDeps) => {
  app.post('/delivery-partners/stripe/account', async (req, res) => {
    if (!stripe) return res.status(500).json({ error: 'stripe_not_configured' });
    try {
      const delivererId = normalizeDelivererId(req.body?.deliverer_id ?? req.body?.delivererId);
      if (!delivererId) return res.status(400).json({ error: 'deliverer_id_required' });

      const exists = await ensureDelivererExists(firestore, delivererId);
      if (!exists) return res.status(404).json({ error: 'deliverer_not_found' });

      const docRef = firestore.collection(DELIVERY_PARTNER_STRIPE).doc(delivererId);
      const existing = await docRef.get();
      const existingAccountId = existing.data()?.stripe?.account_id as string | undefined;
      if (existingAccountId) {
        return res.status(200).json({ account_id: existingAccountId });
      }

      const country = String(req.body?.country || 'US').toUpperCase();
      const businessType = (req.body?.business_type || 'individual') as Stripe.AccountCreateParams.BusinessType;
      const email = req.body?.email ? String(req.body.email).trim() : undefined;
      const phone = req.body?.phone ? String(req.body.phone).trim() : undefined;
      const capabilities = Array.isArray(req.body?.capabilities) ? req.body.capabilities : ['transfers'];
      const capabilityParams = Object.fromEntries(
        capabilities.map((c: string) => [c, { requested: true }]),
      ) as Stripe.AccountCreateParams.Capabilities;

      const accountParams: Stripe.AccountCreateParams = {
        type: 'express',
        country,
        business_type: businessType,
        email: email || undefined,
        capabilities: capabilityParams,
        settings: { payouts: { schedule: { interval: 'manual' } } },
        business_profile: {
          product_description: 'Marketplace courier services',
          support_phone: phone || undefined,
        },
      };

      const account = await stripe.accounts.create(accountParams);

      const payload = buildStripeStatus(account);
      await upsertStripeDoc(firestore, delivererId, payload, 'stripe_account_created', { account_id: account.id });

      res.status(201).json({ account_id: account.id });
    } catch (err: any) {
      console.error('delivery partner stripe account error', err);
      res.status(500).json({ error: 'delivery_partner_stripe_account_failed', message: err.message });
    }
  });

  app.post('/delivery-partners/stripe/account-session', async (req, res) => {
    if (!stripe) return res.status(500).json({ error: 'stripe_not_configured' });
    try {
      const delivererId = normalizeDelivererId(req.body?.deliverer_id ?? req.body?.delivererId);
      if (!delivererId) return res.status(400).json({ error: 'deliverer_id_required' });

      const doc = await firestore.collection(DELIVERY_PARTNER_STRIPE).doc(delivererId).get();
      const accountId = doc.data()?.stripe?.account_id as string | undefined;
      if (!accountId) return res.status(400).json({ error: 'stripe_account_missing' });

      const stripeSession = await stripe.accountSessions.create({
        account: accountId,
        components: {
          account_onboarding: { enabled: true },
          payouts: { enabled: true },
        },
      });

      await appendAudit(doc.ref, 'stripe_account_session', { account_id: accountId });
      res.status(201).json({ client_secret: stripeSession.client_secret });
    } catch (err: any) {
      console.error('delivery partner stripe account session error', err);
      res.status(500).json({ error: 'delivery_partner_stripe_session_failed', message: err.message });
    }
  });

  app.post('/delivery-partners/stripe/embedded-session', async (req, res) => {
    if (!stripe) return res.status(500).json({ error: 'stripe_not_configured' });
    try {
      const delivererId = normalizeDelivererId(req.body?.deliverer_id ?? req.body?.delivererId);
      if (!delivererId) return res.status(400).json({ error: 'deliverer_id_required' });

      const doc = await firestore.collection(DELIVERY_PARTNER_STRIPE).doc(delivererId).get();
      const accountId = doc.data()?.stripe?.account_id as string | undefined;
      if (!accountId) return res.status(400).json({ error: 'stripe_account_missing' });

      const token = await createEmbeddedSession({
        firestore,
        delivererId,
        accountId,
      });

      await appendAudit(doc.ref, 'stripe_embedded_session', { token });

      const baseUrl = baseUrlFromRequest(req, publicBaseUrl);
      res.status(201).json({ url: `${baseUrl}/delivery-partners/stripe/connect/${token}` });
    } catch (err: any) {
      console.error('delivery partner stripe embedded session error', err);
      res.status(500).json({ error: 'delivery_partner_stripe_embedded_session_failed', message: err.message });
    }
  });

  app.post('/delivery-partners/stripe/connect/:token/session', async (req, res) => {
    if (!stripe) return res.status(500).json({ error: 'stripe_not_configured' });
    try {
      const token = String(req.params.token || '').trim();
      if (!token) return res.status(400).json({ error: 'token_required' });
      const doc = await fetchSessionDoc(firestore, token);
      if (!doc) return res.status(404).json({ error: 'session_not_found' });
      const session = doc.data() as DeliveryPartnerStripeSession;
      if (!session || isExpired(session.expires_at)) return res.status(410).json({ error: 'session_expired' });

      const stripeSession = await stripe.accountSessions.create({
        account: session.account_id,
        components: {
          account_onboarding: { enabled: true },
          payouts: { enabled: true },
        },
      });

      await doc.ref.set({ updated_at: Timestamp.now() }, { merge: true });

      res.status(201).json({ client_secret: stripeSession.client_secret });
    } catch (err: any) {
      console.error('delivery partner stripe connect session error', err);
      res.status(500).json({ error: 'delivery_partner_stripe_connect_session_failed', message: err.message });
    }
  });

  app.get('/delivery-partners/stripe/connect/:token', async (req, res) => {
    try {
      const token = String(req.params.token || '').trim();
      if (!token) return res.status(400).send('token_required');
      const doc = await fetchSessionDoc(firestore, token);
      if (!doc) return res.status(404).send('session_not_found');
      const session = doc.data() as DeliveryPartnerStripeSession;
      if (!session || isExpired(session.expires_at)) return res.status(410).send('session_expired');

      const publishableKey = stripePublishableKey || '';
      const baseUrl = baseUrlFromRequest(req, publicBaseUrl);
      const html = buildStripeEmbedHtml({
        publishableKey,
        fetchClientSecretUrl: `${baseUrl}/delivery-partners/stripe/connect/${token}/session`,
        title: 'Complete your payout setup',
        subtitle: 'Stripe will collect the details needed to enable payouts.',
      });
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      res.status(200).send(html);
    } catch (err: any) {
      console.error('delivery partner stripe connect page error', err);
      res.status(500).send('internal_error');
    }
  });

  app.get('/delivery-partners/stripe/status/:delivererId', async (req, res) => {
    try {
      const delivererId = normalizeDelivererId(req.params.delivererId);
      if (!delivererId) return res.status(400).json({ error: 'deliverer_id_required' });
      const doc = await firestore.collection(DELIVERY_PARTNER_STRIPE).doc(delivererId).get();
      if (!doc.exists) return res.status(404).json({ error: 'stripe_not_started' });
      res.status(200).json(doc.data());
    } catch (err: any) {
      console.error('delivery partner stripe status error', err);
      res.status(500).json({ error: 'delivery_partner_stripe_status_failed', message: err.message });
    }
  });
};
