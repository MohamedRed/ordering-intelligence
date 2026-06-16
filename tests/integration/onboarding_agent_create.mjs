import { patchFirestoreDoc } from './lib/firestore_admin.mjs';
import { getOnboardingAuthHeaders } from './lib/onboarding_auth.mjs';

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
if (!projectId) {
  console.error('Missing FIREBASE_PROJECT_ID env var.');
  process.exit(1);
}

const apiBase = baseUrl.replace(/\/$/, '');
const authHeaders = getOnboardingAuthHeaders(apiBase);

const fetchJson = async (url, options = {}) => {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), DEFAULT_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      ...options,
      signal: controller.signal,
      headers: {
        ...authHeaders,
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

  const now = new Date();
  await patchFirestoreDoc({
    projectId,
    documentPath: `onboarding_sessions/${sessionId}`,
    fields: {
      business: {
        name: `CI Agent ${suffix}`,
        type: 'fast_food',
        currency: 'eur',
        phone: '+33123456789',
        address: '1 Rue de Test, Paris',
        timezone: 'Europe/Paris',
      },
      flyers: ['https://cdn.liive.app/demo/menu.png'],
      ingestion: { status: 'succeeded', job_ids: ['job_ci_agent'] },
      updated_at: now,
    },
  });

  const { res: agentRes, data: agentData } = await fetchJson(
    `${apiBase}/onboarding-sessions/${sessionId}/create-agent`,
    { method: 'POST', body: JSON.stringify({}) },
  );
  assertOk('create agent', agentRes, agentData);
  if (!agentData?.agent_id && !agentData?.template_agent_id) {
    throw new Error(`agent create response missing agent_id: ${JSON.stringify(agentData)}`);
  }
  console.log('✓ onboarding agent create ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
