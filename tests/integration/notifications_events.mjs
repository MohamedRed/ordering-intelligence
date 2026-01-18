import { getIdentityToken } from './lib/gcloud_tokens.mjs';
import { patchFirestoreDoc } from './lib/firestore_admin.mjs';

const DEFAULT_TIMEOUT_MS = 20000;
const baseUrl = process.env.NOTIFICATION_SERVICE_BASE_URL;
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const storeId = `test-store-${suffix}`;
const projectId = process.env.FIREBASE_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT || '';
const driverId = (process.env.INTERNAL_DELIVERER_ID || '').trim();

if (!baseUrl) {
  console.error('Missing NOTIFICATION_SERVICE_BASE_URL env var.');
  process.exit(1);
}
if (!projectId) {
  console.error('Missing FIREBASE_PROJECT_ID env var.');
  process.exit(1);
}
if (!driverId) {
  console.error('Missing INTERNAL_DELIVERER_ID env var.');
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

const fetchMetrics = async () => {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), DEFAULT_TIMEOUT_MS);
  try {
    const res = await fetch(`${apiBase}/metrics`, { signal: controller.signal });
    const text = await res.text();
    const metrics = {};
    for (const line of text.split('\n')) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      const [key, value] = trimmed.split(/\s+/);
      metrics[key] = Number(value);
    }
    return metrics;
  } finally {
    clearTimeout(timeout);
  }
};

const assertStatus = async (label, res) => {
  if (!res.ok && res.status !== 204) {
    const text = await res.text();
    throw new Error(`${label} failed: ${res.status} ${text.slice(0, 200)}`);
  }
};

const run = async () => {
  const now = new Date();
  const orderId = `test-order-${suffix}-notify`;
  const driverTokenId = `ci-driver-token-${suffix}`;
  await patchFirestoreDoc({
    projectId,
    documentPath: `deviceTokens/${driverTokenId}`,
    fields: {
      userId: driverId,
      storeId,
      platform: 'web',
      updatedAt: now,
    },
  });
  await patchFirestoreDoc({
    projectId,
    documentPath: `stores/${storeId}`,
    fields: {
      storeId,
      name: 'CI Store',
      delivery_comms: {
        statuses: {
          delivery_assigned: {
            default_channel: 'sms',
          },
        },
        rate_limit_per_hour: 25,
      },
    },
  });
  await patchFirestoreDoc({
    projectId,
    documentPath: `orders/${orderId}`,
    fields: {
      orderId,
      storeId,
      tenantId: `tenant-${suffix}`,
      callerId: '+33123450001',
      customerId: `customer-${suffix}`,
      status: 'confirmed',
      updatedAt: now,
    },
  });

  const before = await fetchMetrics();

  const orderEvent = {
    id: orderId,
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
    driverId,
    orderId,
  };
  const dispatchRes = await fetchJson(`${apiBase}/events/dispatch`, toEnvelope(dispatchEvent));
  await assertStatus('dispatch events', dispatchRes);

  const deliveryEvent = {
    kind: 'delivery_assigned',
    storeId,
    orderId,
    status: 'delivery_assigned',
  };
  const deliveryRes = await fetchJson(`${apiBase}/events/deliveries`, toEnvelope(deliveryEvent));
  await assertStatus('deliveries events', deliveryRes);

  const after = await fetchMetrics();
  const pushDelta = (after.notifications_push_sent_total || 0) - (before.notifications_push_sent_total || 0);
  const smsDelta = (after.notifications_sms_sent_total || 0) - (before.notifications_sms_sent_total || 0);
  const emailDelta = (after.notifications_email_sent_total || 0) - (before.notifications_email_sent_total || 0);
  if (pushDelta <= 0) {
    throw new Error('expected push notifications to increase');
  }
  if (smsDelta <= 0) {
    throw new Error('expected sms notifications to increase');
  }
  if (emailDelta <= 0) {
    throw new Error('expected email notifications to increase');
  }

  console.log('✓ notification events ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
