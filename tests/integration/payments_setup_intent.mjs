import { fetchJson, requestWithRetry } from './lib/payments_test_utils.mjs';

const baseUrl = process.env.PAYMENTS_SERVICE_BASE_URL;
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const tenantId = `test-tenant-${suffix}`;
const customerId = `test-customer-${suffix}`;

if (!baseUrl) {
  console.error('Missing PAYMENTS_SERVICE_BASE_URL env var.');
  process.exit(1);
}

const apiBase = baseUrl.replace(/\/$/, '');

const run = async () => {
  const { data } = await requestWithRetry(
    'setup intent',
    () =>
    fetchJson(
      `${apiBase}/customers/${encodeURIComponent(customerId)}/setup-intent`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ tenantId, customerName: 'CI Customer' })
      },
    ),
    { healthCheckUrl: apiBase },
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
