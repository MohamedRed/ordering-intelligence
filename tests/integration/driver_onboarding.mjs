const DEFAULT_TIMEOUT_MS = 20000;

const baseUrl = process.env.ONBOARDING_BASE_URL;
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const delivererId = `test-deliverer-${suffix}`;

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
  console.log(`Driver onboarding test using deliverer ${delivererId}`);

  const { res: accountRes, data: accountData } = await fetchJson(
    `${apiBase}/delivery-partners/stripe/account`,
    {
      method: 'POST',
      body: JSON.stringify({
        deliverer_id: delivererId,
        country: 'FR',
        business_type: 'individual',
        phone: '+33123450001',
        capabilities: ['transfers'],
      }),
    },
  );
  assertOk('stripe account', accountRes, accountData);
  if (!accountData?.account_id) {
    throw new Error('stripe account response missing account_id');
  }
  console.log(`✓ stripe account ok (${accountData.account_id})`);

  const { res: sessionRes, data: sessionData } = await fetchJson(
    `${apiBase}/delivery-partners/stripe/account-session`,
    {
      method: 'POST',
      body: JSON.stringify({ deliverer_id: delivererId }),
    },
  );
  assertOk('stripe account session', sessionRes, sessionData);
  if (!sessionData?.client_secret) {
    throw new Error('stripe session response missing client_secret');
  }
  console.log('✓ stripe account session ok');

  const { res: complianceRes, data: complianceData } = await fetchJson(
    `${apiBase}/delivery-partners/compliance/start`,
    {
      method: 'POST',
      body: JSON.stringify({
        deliverer_id: delivererId,
        vehicle_type: 'car',
        country: 'FR',
      }),
    },
  );
  assertOk('compliance start', complianceRes, complianceData);
  if (!Array.isArray(complianceData?.required_docs)) {
    throw new Error('compliance response missing required_docs');
  }
  console.log(`✓ compliance start ok (status: ${complianceData.status})`);

  const { res: statusRes, data: statusData } = await fetchJson(
    `${apiBase}/delivery-partners/stripe/status/${delivererId}`,
    { method: 'GET' },
  );
  assertOk('stripe status', statusRes, statusData);
  if (!statusData?.stripe?.account_id) {
    throw new Error('stripe status missing account_id');
  }
  console.log('✓ stripe status ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
