import { getIdentityToken } from './lib/gcloud_tokens.mjs';

const DEFAULT_TIMEOUT_MS = 20000;
const baseUrl = process.env.DELIVERY_SERVICE_BASE_URL;
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const storeId = `test-store-${suffix}`;

if (!baseUrl) {
  console.error('Missing DELIVERY_SERVICE_BASE_URL env var.');
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
  const token = getIdentityToken(apiBase);
  const { res, data } = await fetchJson(`${apiBase}/v1/stores/${storeId}/delivery/quote`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify({
      dropoffLatLng: { lat: 48.857, lng: 2.3522 },
      dropoffAddress: {
        line1: '1 Rue de Test',
        city: 'Paris',
        postalCode: '75001',
        country: 'FR',
        formatted: '1 Rue de Test, 75001 Paris'
      }
    })
  });
  assertOk('delivery quote', res, data);
  if (!data?.provider) {
    throw new Error(`delivery quote missing provider: ${JSON.stringify(data)}`);
  }
  console.log('✓ delivery quote ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
