import { Timestamp } from '@google-cloud/firestore';
import {
  baseUrlFromRequest,
  buildStripeStatus,
  isExpired,
  upsertDeliveryPartnerStripeFromAccount,
} from './delivery_partner_stripe_helpers';

function makeFirestoreWithStripeMatch(match?: { id: string; ref: any }) {
  const whereCalls: any[] = [];
  return {
    whereCalls,
    firestore: {
      collection: (name: string) => ({
        where: (field: string, op: string, value: unknown) => {
          whereCalls.push({ name, field, op, value });
          return {
            limit: () => ({
              get: async () => ({
                empty: !match,
                docs: match ? [{ id: match.id, ref: match.ref }] : [],
              }),
            }),
          };
        },
      }),
    },
  };
}

describe('delivery partner Stripe helpers', () => {
  it('normalizes Stripe account status from requirements and capability flags', () => {
    expect(
      buildStripeStatus({
        id: 'acct_active',
        payouts_enabled: true,
        charges_enabled: true,
        details_submitted: true,
        capabilities: { transfers: 'active' },
        requirements: {},
      } as any),
    ).toMatchObject({
      account_id: 'acct_active',
      status: 'active',
      payouts_enabled: true,
      charges_enabled: true,
      details_submitted: true,
      requirements: { disabled_reason: '' },
    });

    expect(
      buildStripeStatus({
        id: 'acct_disabled',
        requirements: { disabled_reason: 'requirements.past_due', past_due: ['external_account'] },
      } as any),
    ).toMatchObject({
      account_id: 'acct_disabled',
      status: 'requirements.past_due',
      payouts_enabled: false,
      charges_enabled: false,
      details_submitted: false,
      requirements: { past_due: ['external_account'] },
    });
  });

  it('resolves public base URLs from explicit config or forwarded request headers', () => {
    expect(baseUrlFromRequest({} as any, 'https://partners.example.com/')).toBe('https://partners.example.com');
    expect(
      baseUrlFromRequest({
        protocol: 'http',
        headers: {
          'x-forwarded-proto': 'https',
          'x-forwarded-host': 'api.example.com',
        },
      } as any),
    ).toBe('https://api.example.com');
  });

  it('identifies expired embedded sessions', () => {
    expect(isExpired(null)).toBe(true);
    expect(isExpired(Timestamp.fromDate(new Date(Date.now() - 1000)))).toBe(true);
    expect(isExpired(Timestamp.fromDate(new Date(Date.now() + 60_000)))).toBe(false);
  });

  it('syncs delivery partner Stripe docs from account webhook payloads', async () => {
    const setCalls: any[] = [];
    const ref = {
      set: async (payload: any, options?: any) => {
        setCalls.push({ payload, options });
      },
    };
    const { firestore, whereCalls } = makeFirestoreWithStripeMatch({ id: 'deliverer-1', ref });

    await upsertDeliveryPartnerStripeFromAccount(firestore as any, {
      id: 'acct_123',
      payouts_enabled: true,
      details_submitted: true,
      capabilities: { transfers: 'active' },
      requirements: {},
    } as any);

    expect(whereCalls).toEqual([
      { name: 'delivery_partner_stripe', field: 'stripe.account_id', op: '==', value: 'acct_123' },
    ]);
    expect(setCalls[0].payload.stripe).toMatchObject({ account_id: 'acct_123', status: 'active' });
    expect(setCalls[0].options).toEqual({ merge: true });
    expect(setCalls[1].payload.audit).toBeDefined();
    expect(setCalls[1].payload.updated_at).toBeDefined();
  });
});
