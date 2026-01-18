import { getIdentityToken } from './lib/gcloud_tokens.mjs';
import { patchFirestoreDoc } from './lib/firestore_admin.mjs';

const DEFAULT_TIMEOUT_MS = 20000;
const dispatchBaseUrl = process.env.DISPATCH_SERVICE_BASE_URL;
const projectId = process.env.FIREBASE_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT || '';
const delivererId = (process.env.INTERNAL_DELIVERER_ID || '').trim();

if (!dispatchBaseUrl) {
  console.error('Missing DISPATCH_SERVICE_BASE_URL env var.');
  process.exit(1);
}
if (!projectId) {
  console.error('Missing FIREBASE_PROJECT_ID env var.');
  process.exit(1);
}
if (!delivererId) {
  console.error('Missing INTERNAL_DELIVERER_ID env var.');
  process.exit(1);
}

const apiBase = dispatchBaseUrl.replace(/\/$/, '');

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
  const now = new Date();
  await patchFirestoreDoc({
    projectId,
    documentPath: `delivery_partner_stripe/${delivererId}`,
    fields: {
      deliverer_id: delivererId,
      stripe: {
        account_id: 'acct_test_ci',
        status: 'active',
        payouts_enabled: true,
        details_submitted: true
      },
      updated_at: now,
      created_at: now
    }
  });

  await patchFirestoreDoc({
    projectId,
    documentPath: `delivery_partner_compliance/${delivererId}`,
    fields: {
      deliverer_id: delivererId,
      country: 'FR',
      vehicle_type: 'car',
      required_docs: [],
      optional_docs: [],
      status: 'approved',
      updated_at: now,
      created_at: now,
      approved_at: now,
      approval_source: 'ci'
    }
  });

  const token = getIdentityToken(apiBase);
  const authHeader = { Authorization: `Bearer ${token}` };

  const { res: regRes } = await fetchJson(`${apiBase}/v1/marketplace/deliverers/me/register`, {
    method: 'POST',
    headers: authHeader,
    body: JSON.stringify({ displayName: 'CI Deliverer', phoneE164: '+33123450001' })
  });
  assertOk('deliverer register', regRes, null);

  const { res: availRes, data: availData } = await fetchJson(
    `${apiBase}/v1/marketplace/deliverers/me/availability`,
    {
      method: 'POST',
      headers: authHeader,
      body: JSON.stringify({ available: true })
    }
  );
  assertOk('availability', availRes, availData);
  if (availData?.available !== true) {
    throw new Error('availability not set');
  }

  const { res: locRes, data: locData } = await fetchJson(
    `${apiBase}/v1/marketplace/deliverers/me/location`,
    {
      method: 'POST',
      headers: authHeader,
      body: JSON.stringify({ lat: 48.8566, lng: 2.3522, accuracyM: 12 })
    }
  );
  assertOk('location', locRes, locData);
  if (!locData?.lat || !locData?.lng) {
    throw new Error('location not updated');
  }

  console.log('✓ marketplace availability ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
