import { patchFirestoreDoc } from './lib/firestore_admin.mjs';

const DEFAULT_TIMEOUT_MS = 20000;
const baseUrl = process.env.ONBOARDING_BASE_URL;
const projectId = process.env.FIREBASE_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT || '';
const delivererId = (process.env.INTERNAL_DELIVERER_ID || '').trim();

if (!baseUrl) {
  console.error('Missing ONBOARDING_BASE_URL env var.');
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

const apiBase = baseUrl.replace(/\/$/, '');

const fetchJson = async (url, options = {}) => {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), DEFAULT_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      ...options,
      signal: controller.signal,
      headers: {
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

const uploadDoc = async (delivererId, docType) => {
  const form = new FormData();
  const blob = new Blob([`test-${docType}`], { type: 'text/plain' });
  form.append('file', blob, `${docType}.txt`);
  form.append('docType', docType);
  const { res } = await fetchJson(
    `${apiBase}/delivery-partners/compliance/${delivererId}/documents`,
    { method: 'POST', body: form }
  );
  assertOk(`upload ${docType}`, res, null);
};

const run = async () => {
  const now = new Date();
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
      createdAt: now,
      updatedAt: now
    }
  });

  const { res: startRes, data: startData } = await fetchJson(
    `${apiBase}/delivery-partners/compliance/start`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        deliverer_id: delivererId,
        vehicle_type: 'car',
        country: 'FR'
      })
    }
  );
  assertOk('compliance start', startRes, startData);
  const required = startData?.required_docs || [];
  if (!Array.isArray(required) || required.length === 0) {
    throw new Error('required_docs missing from compliance start');
  }

  for (const docType of required) {
    await uploadDoc(delivererId, docType);
  }

  const { res: statusRes, data: statusData } = await fetchJson(
    `${apiBase}/delivery-partners/compliance/${delivererId}`,
    { method: 'GET' }
  );
  assertOk('compliance status', statusRes, statusData);
  if (statusData?.status !== 'approved') {
    throw new Error(`compliance not approved: ${JSON.stringify(statusData)}`);
  }

  console.log('✓ driver compliance upload ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
