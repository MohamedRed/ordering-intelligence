import type express from 'express';
import type Stripe from 'stripe';
import { FieldValue, Firestore, Timestamp } from '@google-cloud/firestore';
import { v4 as uuidv4 } from 'uuid';

export const DELIVERY_PARTNER_STRIPE = 'delivery_partner_stripe';
export const DELIVERY_PARTNER_STRIPE_SESSIONS = 'delivery_partner_stripe_sessions';
export const MARKETPLACE_DELIVERERS = 'marketplace_deliverers';
const EMBED_SESSION_TTL_MINUTES = 30;

type StripeRequirements = {
  currently_due: string[];
  eventually_due: string[];
  past_due: string[];
  pending_verification: string[];
  disabled_reason: string;
};

export type StripeStatusPayload = {
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

export type DeliveryPartnerStripeSession = {
  deliverer_id: string;
  account_id: string;
  created_at: FirebaseFirestore.Timestamp;
  expires_at: FirebaseFirestore.Timestamp;
  updated_at?: FirebaseFirestore.Timestamp;
};

export const normalizeDelivererId = (value: unknown): string => {
  if (typeof value !== 'string') return '';
  return value.trim();
};

export const buildStripeRequirements = (account: Stripe.Account): StripeRequirements => ({
  currently_due: account.requirements?.currently_due ?? [],
  eventually_due: account.requirements?.eventually_due ?? [],
  past_due: account.requirements?.past_due ?? [],
  pending_verification: account.requirements?.pending_verification ?? [],
  disabled_reason: account.requirements?.disabled_reason ?? '',
});

export const buildStripeStatus = (account: Stripe.Account): StripeStatusPayload => {
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

export const appendAudit = async (
  docRef: FirebaseFirestore.DocumentReference,
  event: string,
  data?: any,
) => {
  const ts = Timestamp.now();
  const entry: any = { ts, actor: 'system', event };
  if (data !== undefined) entry.data = data;
  await docRef.set(
    {
      audit: FieldValue.arrayUnion(entry),
      updated_at: ts,
    },
    { merge: true },
  );
};

export const ensureDelivererExists = async (
  firestore: Firestore,
  delivererId: string,
): Promise<boolean> => {
  const snap = await firestore.collection(MARKETPLACE_DELIVERERS).doc(delivererId).get();
  return snap.exists;
};

export const upsertStripeDoc = async (
  firestore: Firestore,
  delivererId: string,
  stripePayload: StripeStatusPayload,
  event: string,
  eventData?: any,
): Promise<void> => {
  const ref = firestore.collection(DELIVERY_PARTNER_STRIPE).doc(delivererId);
  const ts = Timestamp.now();
  const snap = await ref.get();
  const base: Partial<StripeStatusDoc> = snap.exists ? {} : { deliverer_id: delivererId, created_at: ts };
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

export const isExpired = (ts?: FirebaseFirestore.Timestamp | null): boolean => {
  if (!ts) return true;
  return ts.toDate().getTime() <= Date.now();
};

export const baseUrlFromRequest = (req: express.Request, publicBaseUrl?: string): string => {
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

export const createEmbeddedSession = async (params: {
  firestore: Firestore;
  delivererId: string;
  accountId: string;
}): Promise<string> => {
  const token = uuidv4();
  const now = Timestamp.now();
  const expiresAt = Timestamp.fromDate(new Date(Date.now() + EMBED_SESSION_TTL_MINUTES * 60 * 1000));
  const payload: DeliveryPartnerStripeSession = {
    deliverer_id: params.delivererId,
    account_id: params.accountId,
    created_at: now,
    expires_at: expiresAt,
  };
  await params.firestore.collection(DELIVERY_PARTNER_STRIPE_SESSIONS).doc(token).set(payload);
  return token;
};

export const fetchSessionDoc = async (
  firestore: Firestore,
  token: string,
): Promise<FirebaseFirestore.DocumentSnapshot | null> => {
  const doc = await firestore.collection(DELIVERY_PARTNER_STRIPE_SESSIONS).doc(token).get();
  if (!doc.exists) return null;
  return doc;
};
