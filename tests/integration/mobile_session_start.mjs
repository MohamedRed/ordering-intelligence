const DEFAULT_TIMEOUT_MS = 20000;

const baseUrl = process.env.CHANNEL_GATEWAY_BASE_URL;
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const storeId = `test-store-${suffix}`;

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

const run = async () => {
  const payload = {
    provider: 'telegram',
    providerUserId: `ci-telegram-${suffix}`,
    displayName: `CI Telegram ${suffix}`,
    storeId,
    clientPlatform: 'web',
    clientApp: 'consumer-web',
  };
  const { res: startRes, data: startData } = await fetchJson(`${apiBase}/mobile/session/start`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
  assertOk('mobile session start', startRes, startData);

  const sessionId = startData?.sessionId;
  if (!sessionId) {
    throw new Error(`missing sessionId from mobile session start: ${JSON.stringify(startData)}`);
  }
  if (!startData?.customerId) {
    throw new Error(`missing customerId from mobile session start: ${JSON.stringify(startData)}`);
  }

  const { res: getRes, data: getData } = await fetchJson(
    `${apiBase}/mobile/session?sessionId=${encodeURIComponent(sessionId)}`,
    { method: 'GET' },
  );
  assertOk('mobile session get', getRes, getData);
  if (!getData?.customerId) {
    throw new Error(`missing customerId from mobile session get: ${JSON.stringify(getData)}`);
  }
  console.log('✓ mobile session start/get ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
