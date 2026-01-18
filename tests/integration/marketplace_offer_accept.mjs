import { getIdentityToken } from './lib/gcloud_tokens.mjs';
import { patchFirestoreDoc } from './lib/firestore_admin.mjs';

const DEFAULT_TIMEOUT_MS = 20000;
const dispatchBaseUrl = process.env.DISPATCH_SERVICE_BASE_URL;
const projectId = process.env.FIREBASE_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT || '';
const delivererId = (process.env.INTERNAL_DELIVERER_ID || '').trim();
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const storeId = `test-store-${suffix}`;

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
  const offerId = `ci-offer-${Date.now()}`;
  const expiresAt = new Date(Date.now() + 5 * 60 * 1000);
  const locationExpiresAt = new Date(Date.now() + 10 * 60 * 1000);

  await patchFirestoreDoc({
    projectId,
    documentPath: `marketplace_deliverers/${delivererId}`,
    fields: {
      delivererId,
      displayName: 'CI Deliverer',
      phoneE164: '+33123450001',
      status: 'available',
      active: true,
      available: true,
      lat: 48.8566,
      lng: 2.3522,
      accuracyM: 10,
      lastLocationAt: now,
      locationExpiresAt,
      createdAt: now,
      updatedAt: now
    }
  });

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

  await patchFirestoreDoc({
    projectId,
    documentPath: `marketplace_offers/${offerId}`,
    fields: {
      offerId,
      storeId,
      status: 'open',
      payoutCents: 200,
      currency: 'USD',
      candidateIds: [delivererId],
      dropoffLatLng: { lat: 48.857, lng: 2.3522 },
      dropoffAddress: { formatted: '1 Rue de Test, 75001 Paris' },
      acceptedCount: 0,
      createdAt: now,
      updatedAt: now,
      expiresAt
    }
  });

  const token = getIdentityToken(apiBase);
  const { res, data } = await fetchJson(`${apiBase}/v1/marketplace/offers/${offerId}/accept`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` }
  });
  assertOk('offer accept', res, data);
  if (data?.status !== 'accepted') {
    throw new Error(`unexpected accept response: ${JSON.stringify(data)}`);
  }
  console.log('✓ marketplace offer accept ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
