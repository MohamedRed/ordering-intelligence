const DEFAULT_TIMEOUT_MS = 20000;
const baseUrl = process.env.PAYMENTS_SERVICE_BASE_URL;
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const tenantId = `test-tenant-${suffix}`;
const customerId = `test-customer-${suffix}`;

if (!baseUrl) {
  console.error('Missing PAYMENTS_SERVICE_BASE_URL env var.');
  process.exit(1);
}

const apiBase = baseUrl.replace(/\/$/, '');
const RETRYABLE_STATUSES = new Set([502, 503, 504]);

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

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const requestWithRetry = async (label, handler, attempts = 3) => {
  let lastResult = null;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    lastResult = await handler();
    if (lastResult.res.ok) return lastResult;
    if (!RETRYABLE_STATUSES.has(lastResult.res.status)) break;
    if (attempt < attempts) {
      await sleep(500 * attempt);
    }
  }
  assertOk(label, lastResult.res, lastResult.data, lastResult.text);
  return lastResult;
};

const run = async () => {
  const { data } = await requestWithRetry('setup intent', () =>
    fetchJson(
      `${apiBase}/customers/${encodeURIComponent(customerId)}/setup-intent`,
      {
        method: 'POST',
        body: JSON.stringify({ tenantId, customerName: 'CI Customer' })
      },
    ),
  );
  if (!data?.clientSecret) {
    throw new Error('setup intent missing clientSecret');
  }
  console.log('✓ setup intent ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
