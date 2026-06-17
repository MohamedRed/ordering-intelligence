import type express from 'express';
import type Stripe from 'stripe';
import { Firestore, Timestamp } from '@google-cloud/firestore';
import { buildStripeEmbedHtml } from './stripe_embed.js';
import {
  appendAudit,
  baseUrlFromRequest,
  buildStripeStatus,
  createEmbeddedSession,
  DELIVERY_PARTNER_STRIPE,
  type DeliveryPartnerStripeSession,
  ensureDelivererExists,
  fetchSessionDoc,
  isExpired,
  normalizeDelivererId,
  upsertDeliveryPartnerStripeFromAccount,
  upsertStripeDoc,
} from './delivery_partner_stripe_helpers.js';

type DeliveryPartnerStripeDeps = {
  app: express.Express;
  firestore: Firestore;
  stripe: Stripe | null;
  publicBaseUrl?: string;
  stripePublishableKey?: string;
};

export { upsertDeliveryPartnerStripeFromAccount };

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
