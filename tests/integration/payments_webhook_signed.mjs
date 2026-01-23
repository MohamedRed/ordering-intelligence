import crypto from 'node:crypto';
import { getServerTimestamp } from './lib/server_time.mjs';

import { fetchJson, requestWithRetry } from './lib/payments_test_utils.mjs';

const DEFAULT_TIMEOUT_MS = 20000;
const baseUrl = process.env.PAYMENTS_SERVICE_BASE_URL;
const webhookSecret = (process.env.STRIPE_PAYMENTS_WEBHOOK_SECRET || '').trim();
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();

if (!baseUrl) {
  console.error('Missing PAYMENTS_SERVICE_BASE_URL env var.');
  process.exit(1);
}
if (!webhookSecret) {
  console.error('Missing STRIPE_PAYMENTS_WEBHOOK_SECRET env var.');
  process.exit(1);
}

const apiBase = baseUrl.replace(/\/$/, '');

const run = async () => {
  const now = await getServerTimestamp(`${apiBase}/healthz`, DEFAULT_TIMEOUT_MS);
  const event = {
    id: `evt_test_${suffix}_${now}`,
    object: 'event',
    type: 'payment_intent.succeeded',
    livemode: false,
    created: now,
    data: {
      object: {
        id: `pi_test_${suffix}_${now}`,
        object: 'payment_intent',
        metadata: {
          order_id: `test-order-${suffix}-webhook`,
          payment_id: `test-payment-${suffix}`,
          payment_flow: 'capture'
        }
      }
    }
  };

  const payload = JSON.stringify(event);
  const { data } = await requestWithRetry(
    'stripe webhook signed',
    async () => {
      const signatureTimestamp = await getServerTimestamp(
        `${apiBase}/healthz`,
        DEFAULT_TIMEOUT_MS,
      );
      const signedPayload = `${signatureTimestamp}.${payload}`;
      const signature = crypto
        .createHmac('sha256', webhookSecret)
        .update(signedPayload, 'utf8')
        .digest('hex');
      const header = `t=${signatureTimestamp},v1=${signature}`;
      return fetchJson(`${apiBase}/webhooks/stripe`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Stripe-Signature': header,
        },
        body: payload,
      });
    },
    { healthCheckUrl: apiBase },
  );
  if (data?.received !== true) {
    throw new Error(`unexpected webhook response: ${JSON.stringify(data)}`);
  }
  console.log('✓ payments webhook signed ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
