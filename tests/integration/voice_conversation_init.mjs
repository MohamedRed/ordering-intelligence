import { getIdentityToken } from './lib/gcloud_tokens.mjs';
import { getFirestoreDoc } from './lib/firestore_admin.mjs';

const DEFAULT_TIMEOUT_MS = 20000;
const baseUrl = process.env.AGENT_WEBHOOKS_BASE_URL;
const projectId = process.env.FIREBASE_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT || '';
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const storeId = `test-store-${suffix}`;
const agentId = `agent-${suffix}-voice`;
const tenantId = `tenant-${suffix}`;

if (!baseUrl) {
  console.error('Missing AGENT_WEBHOOKS_BASE_URL env var.');
  process.exit(1);
}
if (!projectId) {
  console.error('Missing FIREBASE_PROJECT_ID env var.');
  process.exit(1);
}

const apiBase = baseUrl.replace(/\/$/, '');
const token = getIdentityToken(apiBase);

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

const run = async () => {
  const payload = {
    agent_id: agentId,
    agent_number: '+33123456789',
    phone_number_id: 'pn-test',
    caller_id: '+33987654321',
    store_id: storeId,
    tenant_id: tenantId,
    business_type: 'restaurant',
    onboarding_session_id: `onb-${suffix}`,
    dynamic_variables: {
      storeId,
      tenantId,
      businessType: 'restaurant'
    }
  };

  const { res, data } = await fetchJson(`${apiBase}/internal/test/conversation-init`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`
    },
    body: JSON.stringify(payload)
  });
  assertOk('conversation init', res, data);

  const doc = await getFirestoreDoc({
    projectId,
    documentPath: `agent_webhook_events/agent_${agentId}`
  });
  if (!doc?.fields) {
    throw new Error('conversation init event not found');
  }
  const stored = doc.fields.dynamic_variables || {};
  if (stored.storeId !== storeId) {
    throw new Error(`unexpected storeId in dynamic variables: ${JSON.stringify(stored)}`);
  }

  console.log('✓ voice conversation init ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
