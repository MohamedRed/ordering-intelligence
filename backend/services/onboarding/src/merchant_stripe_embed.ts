import type express from 'express';
import type Stripe from 'stripe';
import { Firestore, Timestamp } from '@google-cloud/firestore';
import { v4 as uuidv4 } from 'uuid';
import { buildStripeEmbedHtml } from './stripe_embed.js';

type MerchantStripeEmbedDeps = {
  app: express.Express;
  firestore: Firestore;
  stripe: Stripe | null;
  publicBaseUrl?: string;
  stripePublishableKey?: string;
};

type MerchantStripeSession = {
  session_id: string;
  account_id: string;
  created_at: FirebaseFirestore.Timestamp;
  expires_at: FirebaseFirestore.Timestamp;
  updated_at?: FirebaseFirestore.Timestamp;
};

const MERCHANT_STRIPE_SESSIONS = 'onboarding_stripe_sessions';
const SESSION_TTL_MINUTES = 30;

const baseUrlFromRequest = (req: express.Request, publicBaseUrl?: string): string => {
  if (publicBaseUrl && publicBaseUrl.trim().length > 0) {
    return publicBaseUrl.replace(/\/$/, '');
  }
  const proto = (req.headers['x-forwarded-proto'] || req.protocol || 'https') as string;
  const host = (req.headers['x-forwarded-host'] || req.headers['host'] || '').toString();
  return `${proto}://${host}`.replace(/\/$/, '');
};

const isExpired = (ts?: FirebaseFirestore.Timestamp | null): boolean => {
  if (!ts) return true;
  return ts.toDate().getTime() <= Date.now();
};

const createEmbedSessionToken = async (
  firestore: Firestore,
  sessionId: string,
  accountId: string,
): Promise<string> => {
  const token = uuidv4();
  const now = Timestamp.now();
  const expiresAt = Timestamp.fromDate(
    new Date(Date.now() + SESSION_TTL_MINUTES * 60 * 1000),
  );
  const payload: MerchantStripeSession = {
    session_id: sessionId,
    account_id: accountId,
    created_at: now,
    expires_at: expiresAt,
  };
  await firestore.collection(MERCHANT_STRIPE_SESSIONS).doc(token).set(payload);
  return token;
};

const fetchSessionToken = async (
  firestore: Firestore,
  token: string,
): Promise<FirebaseFirestore.DocumentSnapshot | null> => {
  const doc = await firestore.collection(MERCHANT_STRIPE_SESSIONS).doc(token).get();
  if (!doc.exists) return null;
  return doc;
};

export const registerMerchantStripeEmbedRoutes = ({
  app,
  firestore,
  stripe,
  publicBaseUrl,
  stripePublishableKey,
}: MerchantStripeEmbedDeps) => {
  app.post('/stripe/embedded-session', async (req, res) => {
    if (!stripe) return res.status(500).json({ error: 'stripe_not_configured' });
    try {
      const sessionId = String(req.body?.session_id || '').trim();
      if (!sessionId) return res.status(400).json({ error: 'session_id_required' });
      const sessionDoc = await firestore.collection('onboarding_sessions').doc(sessionId).get();
      if (!sessionDoc.exists) return res.status(404).json({ error: 'session_not_found' });
      const accountId = sessionDoc.data()?.stripe?.account_id as string | undefined;
      if (!accountId) return res.status(400).json({ error: 'account_id_missing_for_session' });

      const token = await createEmbedSessionToken(firestore, sessionId, accountId);
      const baseUrl = baseUrlFromRequest(req, publicBaseUrl);
      res.status(201).json({ url: `${baseUrl}/stripe/connect/${token}` });
    } catch (err: any) {
      console.error('merchant stripe embedded session error', err);
      res.status(500).json({ error: 'stripe_embedded_session_failed', message: err.message });
    }
  });

  app.post('/stripe/connect/:token/session', async (req, res) => {
    if (!stripe) return res.status(500).json({ error: 'stripe_not_configured' });
    try {
      const token = String(req.params.token || '').trim();
      if (!token) return res.status(400).json({ error: 'token_required' });
      const doc = await fetchSessionToken(firestore, token);
      if (!doc) return res.status(404).json({ error: 'session_not_found' });
      const session = doc.data() as MerchantStripeSession;
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
      console.error('merchant stripe connect session error', err);
      res.status(500).json({ error: 'stripe_connect_session_failed', message: err.message });
    }
  });

  app.get('/stripe/connect/:token', async (req, res) => {
    try {
      const token = String(req.params.token || '').trim();
      if (!token) return res.status(400).send('token_required');
      const doc = await fetchSessionToken(firestore, token);
      if (!doc) return res.status(404).send('session_not_found');
      const session = doc.data() as MerchantStripeSession;
      if (!session || isExpired(session.expires_at)) return res.status(410).send('session_expired');

      const publishableKey = stripePublishableKey || '';
      const baseUrl = baseUrlFromRequest(req, publicBaseUrl);
      const html = buildStripeEmbedHtml({
        publishableKey,
        fetchClientSecretUrl: `${baseUrl}/stripe/connect/${token}/session`,
        title: 'Complete Stripe onboarding',
        subtitle: 'Stripe will collect the details needed to enable payouts and verification.',
      });
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      res.status(200).send(html);
    } catch (err: any) {
      console.error('merchant stripe connect page error', err);
      res.status(500).send('internal_error');
    }
  });
};
