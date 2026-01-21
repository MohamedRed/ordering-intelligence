import { getIdentityToken } from './lib/gcloud_tokens.mjs';
import { fetchJson, requestWithRetry } from './lib/payments_test_utils.mjs';

const baseUrl = process.env.PAYMENTS_SERVICE_BASE_URL;
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();

if (!baseUrl) {
  console.error('Missing PAYMENTS_SERVICE_BASE_URL env var.');
  process.exit(1);
}

const apiBase = baseUrl.replace(/\/$/, '');
const token = getIdentityToken(apiBase);

const run = async () => {
  const now = Math.floor(Date.now() / 1000);
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
          payment_flow: 'capture',
        },
      },
    },
  };

  const { data } = await requestWithRetry('stripe webhook', () =>
    fetchJson(`${apiBase}/internal/test/stripe-webhook`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(event),
    }),
  );
  if (data?.received !== true) {
    throw new Error(`unexpected webhook response: ${JSON.stringify(data)}`);
  }
  console.log('✓ payments webhook test ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
