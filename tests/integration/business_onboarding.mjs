import { patchFirestoreDoc } from './lib/firestore_admin.mjs';

const DEFAULT_TIMEOUT_MS = 20000;
const baseUrl = process.env.ONBOARDING_BASE_URL;
const projectId = process.env.FIREBASE_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT || '';
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const tenantId = `test-tenant-${suffix}`;
const storeId = `test-store-${suffix}`;

if (!baseUrl) {
  console.error('Missing ONBOARDING_BASE_URL env var.');
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
  const { res: sessionRes, data: sessionData } = await fetchJson(
    `${apiBase}/onboarding-sessions`,
    {
      method: 'POST',
      body: JSON.stringify({ tenant_id: tenantId, store_id: storeId }),
    },
  );
  assertOk('create session', sessionRes, sessionData);
  const sessionId = sessionData?.session_id;
  if (!sessionId) {
    throw new Error('session creation missing session_id');
  }
  console.log(`✓ onboarding session ok (${sessionId})`);

  const { res: accountRes, data: accountData } = await fetchJson(
    `${apiBase}/stripe/account`,
    {
      method: 'POST',
      body: JSON.stringify({
        session_id: sessionId,
        business_type: 'company',
        capabilities: ['card_payments', 'transfers'],
      }),
    },
  );
  assertOk('stripe account', accountRes, accountData);
  if (!accountData?.account_id) {
    throw new Error('stripe account missing account_id');
  }
  console.log(`✓ stripe account ok (${accountData.account_id})`);

  if (projectId) {
    await patchFirestoreDoc({
      projectId,
      documentPath: `tenants/${tenantId}`,
      fields: {
        stripe_account_id: accountData.account_id,
        stripeAccountId: accountData.account_id
      }
    });
    console.log('✓ tenant stripe account updated');
  }

  const { res: sessionStripeRes, data: sessionStripeData } = await fetchJson(
    `${apiBase}/stripe/account-session`,
    {
      method: 'POST',
      body: JSON.stringify({ session_id: sessionId }),
    },
  );
  assertOk('stripe account session', sessionStripeRes, sessionStripeData);
  if (!sessionStripeData?.client_secret) {
    throw new Error('stripe account session missing client_secret');
  }
  console.log('✓ stripe account session ok');

  const { res: statusRes, data: statusData } = await fetchJson(
    `${apiBase}/onboarding-sessions/${sessionId}/status`,
    { method: 'GET' },
  );
  assertOk('onboarding status', statusRes, statusData);
  console.log('✓ onboarding status ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
