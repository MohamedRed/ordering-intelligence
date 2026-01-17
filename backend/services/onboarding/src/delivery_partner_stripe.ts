import type express from 'express';
import type Stripe from 'stripe';
import { FieldValue, Firestore, Timestamp } from '@google-cloud/firestore';

const DELIVERY_PARTNER_STRIPE = 'delivery_partner_stripe';
const MARKETPLACE_DELIVERERS = 'marketplace_deliverers';

const defaultReturnUrl = 'https://driver.onboarding/stripe/return';
const defaultRefreshUrl = 'https://driver.onboarding/stripe/refresh';

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

type DeliveryPartnerStripeDeps = {
  app: express.Express;
  firestore: Firestore;
  stripe: Stripe | null;
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

export const registerDeliveryPartnerStripeRoutes = ({ app, firestore, stripe }: DeliveryPartnerStripeDeps) => {
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

  app.post('/delivery-partners/stripe/account-link', async (req, res) => {
    if (!stripe) return res.status(500).json({ error: 'stripe_not_configured' });
    try {
      const delivererId = normalizeDelivererId(req.body?.deliverer_id ?? req.body?.delivererId);
      if (!delivererId) return res.status(400).json({ error: 'deliverer_id_required' });

      const docRef = firestore.collection(DELIVERY_PARTNER_STRIPE).doc(delivererId);
      const doc = await docRef.get();
      const accountId = doc.data()?.stripe?.account_id as string | undefined;
      if (!accountId) return res.status(400).json({ error: 'stripe_account_missing' });

      const refreshUrl = String(req.body?.refresh_url || defaultRefreshUrl);
      const returnUrl = String(req.body?.return_url || defaultReturnUrl);

      const link = await stripe.accountLinks.create({
        account: accountId,
        refresh_url: refreshUrl,
        return_url: returnUrl,
        type: 'account_onboarding',
      });

      await appendAudit(docRef, 'stripe_account_link', { account_id: accountId });
      res.status(201).json({ url: link.url });
    } catch (err: any) {
      console.error('delivery partner stripe account link error', err);
      res.status(500).json({ error: 'delivery_partner_stripe_link_failed', message: err.message });
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
