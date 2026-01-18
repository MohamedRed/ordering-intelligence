import { getIdentityToken } from './lib/gcloud_tokens.mjs';
import { patchFirestoreDoc } from './lib/firestore_admin.mjs';

const DEFAULT_TIMEOUT_MS = 20000;
const baseUrl = process.env.DISPATCH_SERVICE_BASE_URL;
const projectId = process.env.FIREBASE_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT || '';
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const storeId = `test-store-${suffix}`;
const driverId = (process.env.INTERNAL_DELIVERER_ID || '').trim();
const routeId = `route-${suffix}`;
const deliveryId = `delivery-${suffix}`;

if (!baseUrl) {
  console.error('Missing DISPATCH_SERVICE_BASE_URL env var.');
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

const fetchJson = async (url, options = {}) => {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), DEFAULT_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      ...options,
      signal: controller.signal,
      headers: {
        ...(options.headers || {}),
        Authorization: `Bearer ${token}`
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
  const now = new Date();
  await patchFirestoreDoc({
    projectId,
    documentPath: `stores/${storeId}/drivers/${driverId}`,
    fields: {
      uid: driverId,
      active: true,
      available: true,
      status: 'available',
      updatedAt: now
    }
  });

  await patchFirestoreDoc({
    projectId,
    documentPath: `stores/${storeId}/routes/${routeId}`,
    fields: {
      routeId,
      driverId,
      deliveryIds: [deliveryId],
      status: 'planned',
      createdAt: now,
      updatedAt: now
    }
  });

  const optimizePayload = {
    locations: [
      { lat: 48.8566, lng: 2.3522 },
      { lat: 48.8584, lng: 2.2945 }
    ],
    mode: 'car',
    units: 'metric'
  };
  const { res: optRes, data: optData } = await fetchJson(`${apiBase}/v1/stores/${storeId}/routes/optimize`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(optimizePayload)
  });
  assertOk('route optimize', optRes, optData);

  const { res: statusRes, data: statusData } = await fetchJson(
    `${apiBase}/v1/stores/${storeId}/routes/${routeId}/stops/${deliveryId}/status`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'picked_up' })
    }
  );
  assertOk('route stop status', statusRes, statusData);

  const { res: currentRes, data: currentData } = await fetchJson(
    `${apiBase}/v1/stores/${storeId}/drivers/routes/current`,
    { method: 'GET' }
  );
  assertOk('current route', currentRes, currentData);
  if (currentData?.routeId !== routeId) {
    throw new Error(`unexpected routeId: ${JSON.stringify(currentData)}`);
  }

  console.log('✓ driver route lifecycle ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
