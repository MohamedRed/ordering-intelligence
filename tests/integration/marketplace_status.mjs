import { getIdentityToken } from './lib/gcloud_tokens.mjs';

const DEFAULT_TIMEOUT_MS = 20000;
const dispatchBaseUrl = process.env.DISPATCH_SERVICE_BASE_URL;
const orderBaseUrl = process.env.ORDER_SERVICE_BASE_URL;
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const tenantId = `test-tenant-${suffix}`;
const storeId = `test-store-${suffix}`;
const customerId = `test-customer-${suffix}`;

if (!dispatchBaseUrl) {
  console.error('Missing DISPATCH_SERVICE_BASE_URL env var.');
  process.exit(1);
}
if (!orderBaseUrl) {
  console.error('Missing ORDER_SERVICE_BASE_URL env var.');
  process.exit(1);
}

const dispatchApi = dispatchBaseUrl.replace(/\/$/, '');
const orderApi = orderBaseUrl.replace(/\/$/, '');

const fetchJson = async (url, options = {}) => {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), DEFAULT_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      ...options,
      signal: controller.signal,
      headers: {
        'Content-Type': 'application/json',
        ...(options.headers || {})
      }
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
  const orderToken = getIdentityToken(orderApi);
  const dispatchToken = getIdentityToken(dispatchApi);

  const { res: orderRes, data: order } = await fetchJson(`${orderApi}/orders`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${orderToken}` },
    body: JSON.stringify({
      storeId,
      tenantId,
      customerId,
      channel: 'webapp',
      callSid: `ci-marketplace-${Date.now()}`,
      customerName: 'CI Marketplace',
      callerId: '+33123456789',
      businessType: 'restaurant',
      paymentMethod: 'cash',
      fulfillmentType: 'delivery',
      delivery: {
        fleetMode: 'marketplace',
        dropoffLatLng: { lat: 48.857, lng: 2.3522 },
        dropoffAddress: {
          line1: '1 Rue de Test',
          city: 'Paris',
          postalCode: '75001',
          country: 'FR',
          formatted: '1 Rue de Test, 75001 Paris'
        }
      },
      items: [
        {
          itemId: 'test-pizza',
          name: 'Test Pizza',
          quantity: 1,
          priceCents: 1200,
          category: 'Pizza',
          modifiers: []
        }
      ]
    })
  });
  assertOk('create order', orderRes, order);
  if (!order?.id) {
    throw new Error('order response missing id');
  }

  const { res, data } = await fetchJson(
    `${dispatchApi}/v1/marketplace/orders/${order.id}/status`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${dispatchToken}` },
      body: JSON.stringify({ status: 'out_for_delivery', storeId })
    }
  );
  assertOk('marketplace order status', res, data);
  if (data?.status !== 'ok') {
    throw new Error(`unexpected marketplace status response: ${JSON.stringify(data)}`);
  }
  console.log('✓ marketplace status update ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
