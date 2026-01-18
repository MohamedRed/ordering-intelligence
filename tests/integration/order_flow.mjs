import { getIdentityToken } from './lib/gcloud_tokens.mjs';

const DEFAULT_TIMEOUT_MS = 20000;
const baseUrl = process.env.ORDER_SERVICE_BASE_URL;
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const storeId = `test-store-${suffix}`;
const tenantId = `test-tenant-${suffix}`;
const customerId = `test-customer-${suffix}`;

if (!baseUrl) {
  console.error('Missing ORDER_SERVICE_BASE_URL env var.');
  process.exit(1);
}

const apiBase = baseUrl.replace(/\/$/, '');

const fetchJson = async (url, options = {}) => {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), DEFAULT_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      ...options,
      signal: controller.signal,
      headers: {
        'Content-Type': 'application/json',
        ...(options.headers || {}),
      },
    });
    const text = await res.text();
    const data = text ? JSON.parse(text) : null;
    return { res, data };
  } finally {
    clearTimeout(timeout);
  }
};

const assertOk = (label, res, data) => {
  if (!(res.status >= 200 && res.status < 300)) {
    const payload = data ? JSON.stringify(data) : 'no body';
    throw new Error(`${label} failed: ${res.status} ${payload}`);
  }
};

const run = async () => {
  const token = getIdentityToken(apiBase);
  const authHeader = { Authorization: `Bearer ${token}` };

  const { res: createRes, data: order } = await fetchJson(`${apiBase}/orders`, {
    method: 'POST',
    headers: authHeader,
    body: JSON.stringify({
      storeId,
      tenantId,
      customerId,
      channel: 'webapp',
      callSid: `ci-call-${Date.now()}`,
      customerName: 'CI Customer',
      callerId: '+33123456789',
      businessType: 'restaurant',
      paymentMethod: 'cash',
      fulfillmentType: 'pickup',
      items: [
        {
          itemId: 'test-pizza',
          name: 'Test Pizza',
          quantity: 1,
          priceCents: 1200,
          category: 'Pizza',
          modifiers: [],
        },
      ],
    }),
  });
  assertOk('create order', createRes, order);
  if (!order?.id) {
    throw new Error('order response missing id');
  }
  console.log(`✓ order created (${order.id})`);

  const { res: getRes, data: fetched } = await fetchJson(`${apiBase}/orders/${order.id}`, {
    method: 'GET',
    headers: authHeader,
  });
  assertOk('fetch order', getRes, fetched);
  if (fetched?.id !== order.id) {
    throw new Error('fetched order mismatch');
  }
  console.log('✓ order fetch ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
