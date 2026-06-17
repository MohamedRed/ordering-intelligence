import { getIdentityToken } from './lib/gcloud_tokens.mjs';

const DEFAULT_TIMEOUT_MS = 20000;
const baseUrl = process.env.CHANNEL_GATEWAY_BASE_URL;
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const storeId = `test-store-${suffix}`;

if (!baseUrl) {
  console.error('Missing CHANNEL_GATEWAY_BASE_URL env var.');
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
        'Content-Type': 'application/json',
        ...(options.headers || {}),
      },
    });
    const text = await res.text();
    let data = null;
    if (text) {
      try {
        data = JSON.parse(text);
      } catch (_) {
        data = null;
      }
    }
    return { res, data, text };
  } finally {
    clearTimeout(timeout);
  }
};

const assertOk = (label, res, data, text) => {
  if (!res.ok) {
    const payload = data ? JSON.stringify(data) : text || 'no body';
    throw new Error(`${label} failed: ${res.status} ${payload}`);
  }
};

const createSession = async () => {
  const { res, data, text } = await fetchJson(`${apiBase}/internal/test/webapp/session`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({
      channel: 'telegram_webapp',
      userId: `ci-delivery-prewarm-${suffix}`,
      displayName: `CI Delivery ${suffix}`,
      storeId,
    }),
  });
  assertOk('create webapp session', res, data, text);
  if (!data?.sessionId) {
    throw new Error(`missing sessionId: ${JSON.stringify(data)}`);
  }
  if (data?.storeId !== storeId) {
    throw new Error(`unexpected session store: ${JSON.stringify(data)}`);
  }
  return data.sessionId;
};

const run = async () => {
  const sessionId = await createSession();
  const prewarmPayload = {
    sessionId,
    dropoffLatLng: { lat: 48.857, lng: 2.3522 },
    dropoffAddress: { formatted: '1 Rue de Test, 75001 Paris' },
  };

  const { res, data, text } = await fetchJson(`${apiBase}/telegram/webapp/delivery/prewarm`, {
    method: 'POST',
    body: JSON.stringify(prewarmPayload),
  });
  assertOk('webapp delivery prewarm', res, data, text);
  if (data?.status !== 'ok') {
    throw new Error(`webapp delivery prewarm unexpected status: ${JSON.stringify(data)}`);
  }

  const override = await fetchJson(`${apiBase}/telegram/webapp/delivery/prewarm`, {
    method: 'POST',
    body: JSON.stringify({
      ...prewarmPayload,
      storeId: `${storeId}-other`,
    }),
  });
  if (override.res.status !== 403) {
    const payload = override.data ? JSON.stringify(override.data) : override.text || 'no body';
    throw new Error(`store override should be forbidden: ${override.res.status} ${payload}`);
  }

  console.log('✓ webapp delivery prewarm ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
