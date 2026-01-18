import { getIdentityToken } from './lib/gcloud_tokens.mjs';

const DEFAULT_TIMEOUT_MS = 20000;
const orderBaseUrl = process.env.ORDER_SERVICE_BASE_URL;
const deliveryBaseUrl = process.env.DELIVERY_SERVICE_BASE_URL;
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const storeId = `test-store-${suffix}`;
const tenantId = `test-tenant-${suffix}`;
const customerId = `test-customer-${suffix}`;

if (!orderBaseUrl) {
  console.error('Missing ORDER_SERVICE_BASE_URL env var.');
  process.exit(1);
}
if (!deliveryBaseUrl) {
  console.error('Missing DELIVERY_SERVICE_BASE_URL env var.');
  process.exit(1);
}

const orderApi = orderBaseUrl.replace(/\/$/, '');
const deliveryApi = deliveryBaseUrl.replace(/\/$/, '');

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
  const orderToken = getIdentityToken(orderApi);
  const deliveryToken = getIdentityToken(deliveryApi);

  const { res: createRes, data: order } = await fetchJson(`${orderApi}/orders`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${orderToken}` },
    body: JSON.stringify({
      storeId,
      tenantId,
      customerId,
      channel: 'webapp',
      callSid: `ci-delivery-${Date.now()}`,
      customerName: 'CI Delivery',
      callerId: '+33123456789',
      businessType: 'restaurant',
      paymentMethod: 'cash',
      fulfillmentType: 'delivery',
      delivery: {
        fleetMode: 'third_party',
        dropoffLatLng: { lat: 48.857, lng: 2.3522 },
        dropoffAddress: {
          line1: '1 Rue de Test',
          city: 'Paris',
          postalCode: '75001',
          country: 'FR',
          formatted: '1 Rue de Test, 75001 Paris',
        },
      },
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
  assertOk('create delivery order', createRes, order);
  if (!order?.id) {
    throw new Error('order response missing id');
  }
  console.log(`✓ delivery order created (${order.id})`);

  const { res: dispatchRes, data: dispatchData } = await fetchJson(
    `${deliveryApi}/v1/orders/${order.id}/delivery/dispatch`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${deliveryToken}` },
      body: JSON.stringify({ storeId }),
    },
  );
  assertOk('delivery dispatch', dispatchRes, dispatchData);
  if (!dispatchData?.deliveryId) {
    throw new Error('delivery dispatch missing deliveryId');
  }
  console.log(`✓ delivery dispatch ok (${dispatchData.deliveryId})`);
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
