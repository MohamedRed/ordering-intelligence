import { getIdentityToken } from './lib/gcloud_tokens.mjs';

const DEFAULT_TIMEOUT_MS = 20000;
const baseUrl = process.env.DISPATCH_SERVICE_BASE_URL;
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const storeId = `test-store-${suffix}`;

if (!baseUrl) {
  console.error('Missing DISPATCH_SERVICE_BASE_URL env var.');
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

  const { res, data } = await fetchJson(`${apiBase}/v1/stores/${storeId}/marketplace/prewarm`, {
    method: 'POST',
    headers: authHeader,
    body: JSON.stringify({
      dropoffLatLng: { lat: 48.857, lng: 2.3522 },
      dropoffAddress: { formatted: '1 Rue de Test, 75001 Paris' },
    }),
  });
  assertOk('dispatch prewarm', res, data);
  if (data?.status !== 'ok') {
    throw new Error(`dispatch prewarm unexpected status: ${JSON.stringify(data)}`);
  }
  console.log('✓ dispatch prewarm ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
