import { createHmac } from 'node:crypto';

const DEFAULT_TIMEOUT_MS = 20000;

const baseUrl = process.env.CHANNEL_GATEWAY_BASE_URL;
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const storeId = `test-store-${suffix}`;
const mobileSessionSecret = (process.env.MOBILE_SESSION_SHARED_SECRET || '').trim();

if (!baseUrl) {
  console.error('Missing CHANNEL_GATEWAY_BASE_URL env var.');
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
  if (!res.ok) {
    const payload = data ? JSON.stringify(data) : 'no body';
    throw new Error(`${label} failed: ${res.status} ${payload}`);
  }
};

const signMobileAuth = (...parts) => {
  if (!mobileSessionSecret) {
    return {};
  }
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const signature = createHmac('sha256', mobileSessionSecret)
    .update([...parts, timestamp].join(':'))
    .digest('hex');
  return { signature, timestamp };
};

const run = async () => {
  const payload = {
    provider: 'telegram',
    providerUserId: `ci-telegram-${suffix}`,
    displayName: `CI Telegram ${suffix}`,
    storeId,
    clientPlatform: 'web',
    clientApp: 'consumer-web',
  };
  Object.assign(payload, signMobileAuth(payload.provider, payload.providerUserId));
  const { res: startRes, data: startData } = await fetchJson(`${apiBase}/mobile/session/start`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
  assertOk('mobile session start', startRes, startData);

  const sessionId = startData?.sessionId;
  if (!sessionId) {
    throw new Error(`missing sessionId from mobile session start: ${JSON.stringify(startData)}`);
  }
  const startUserId = startData?.customerId || startData?.userId;
  if (!startUserId) {
    throw new Error(`missing user identity from mobile session start: ${JSON.stringify(startData)}`);
  }
  if (startData?.storeId && startData.storeId !== storeId) {
    throw new Error(`unexpected storeId from mobile session start: ${JSON.stringify(startData)}`);
  }

  const getUrl = new URL(`${apiBase}/mobile/session`);
  getUrl.searchParams.set('sessionId', sessionId);
  const getProof = signMobileAuth('session', sessionId);
  if (getProof.signature) {
    getUrl.searchParams.set('signature', getProof.signature);
    getUrl.searchParams.set('timestamp', getProof.timestamp);
  }
  const { res: getRes, data: getData } = await fetchJson(getUrl.toString(), { method: 'GET' });
  assertOk('mobile session get', getRes, getData);
  const getUserId = getData?.customerId || getData?.userId;
  if (!getUserId) {
    throw new Error(`missing user identity from mobile session get: ${JSON.stringify(getData)}`);
  }
  if (getData?.storeId && getData.storeId !== storeId) {
    throw new Error(`unexpected storeId from mobile session get: ${JSON.stringify(getData)}`);
  }
  console.log('✓ mobile session start/get ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
