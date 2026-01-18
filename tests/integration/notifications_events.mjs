import { getIdentityToken } from './lib/gcloud_tokens.mjs';

const DEFAULT_TIMEOUT_MS = 20000;
const baseUrl = process.env.NOTIFICATION_SERVICE_BASE_URL;
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const storeId = `test-store-${suffix}`;

if (!baseUrl) {
  console.error('Missing NOTIFICATION_SERVICE_BASE_URL env var.');
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
    return res;
  } finally {
    clearTimeout(timeout);
  }
};

const toEnvelope = (data) => ({
  message: {
    data: Buffer.from(JSON.stringify(data)).toString('base64'),
  },
});

const assertStatus = async (label, res) => {
  if (!res.ok && res.status !== 204) {
    const text = await res.text();
    throw new Error(`${label} failed: ${res.status} ${text.slice(0, 200)}`);
  }
};

const run = async () => {
  const orderEvent = {
    id: `test-order-${suffix}-notify`,
    storeId,
    status: 'confirmed',
    customerName: 'CI Tester',
    totalCents: 1500,
    statusChange: {
      previousStatus: 'pending',
      newStatus: 'confirmed',
    },
  };
  const orderRes = await fetchJson(`${apiBase}/events/orders`, toEnvelope(orderEvent));
  await assertStatus('orders events', orderRes);

  const dispatchEvent = {
    kind: 'assignment_request',
    storeId,
    assignmentId: `assign-${suffix}`,
  };
  const dispatchRes = await fetchJson(`${apiBase}/events/dispatch`, toEnvelope(dispatchEvent));
  await assertStatus('dispatch events', dispatchRes);

  const deliveryEvent = {
    kind: 'delivery_assigned',
    storeId,
    orderId: `test-order-${suffix}-notify`,
    status: 'delivery_assigned',
  };
  const deliveryRes = await fetchJson(`${apiBase}/events/deliveries`, toEnvelope(deliveryEvent));
  await assertStatus('deliveries events', deliveryRes);

  console.log('✓ notification events ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
