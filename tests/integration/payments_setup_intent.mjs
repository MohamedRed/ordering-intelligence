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
  const { res, data } = await fetchJson(
    `${apiBase}/customers/${encodeURIComponent(customerId)}/setup-intent`,
    {
      method: 'POST',
      body: JSON.stringify({ tenantId, customerName: 'CI Customer' })
    }
  );
  assertOk('setup intent', res, data);
  if (!data?.clientSecret) {
    throw new Error('setup intent missing clientSecret');
  }
  console.log('✓ setup intent ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
