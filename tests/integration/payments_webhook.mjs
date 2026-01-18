import { getIdentityToken } from './lib/gcloud_tokens.mjs';

const DEFAULT_TIMEOUT_MS = 20000;
const baseUrl = process.env.PAYMENTS_SERVICE_BASE_URL;
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();

if (!baseUrl) {
  console.error('Missing PAYMENTS_SERVICE_BASE_URL env var.');
  process.exit(1);
}

const apiBase = baseUrl.replace(/\/$/, '');
const token = getIdentityToken(apiBase);

const fetchJson = async (url, payload) => {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), DEFAULT_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      method: 'POST',
      signal: controller.signal,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(payload),
    });
    const text = await res.text();
    const data = text ? JSON.parse(text) : null;
    return { res, data };
  } finally {
    clearTimeout(timeout);
  }
};

const assertOk = (label, res, data) => {
  if (!res.ok) {
    const payload = data ? JSON.stringify(data) : 'no body';
    throw new Error(`${label} failed: ${res.status} ${payload}`);
  }
};

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

  const { res, data } = await fetchJson(`${apiBase}/internal/test/stripe-webhook`, event);
  assertOk('stripe webhook', res, data);
  if (data?.received !== true) {
    throw new Error(`unexpected webhook response: ${JSON.stringify(data)}`);
  }
  console.log('✓ payments webhook test ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
