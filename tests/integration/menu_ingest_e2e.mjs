import { getIdentityToken } from './lib/gcloud_tokens.mjs';

const DEFAULT_TIMEOUT_MS = 20000;
const ingestBaseUrl = process.env.MENU_INGESTION_BASE_URL;
const orderBaseUrl = process.env.ORDER_SERVICE_BASE_URL;
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const storeId = `test-store-${suffix}`;

if (!ingestBaseUrl) {
  console.error('Missing MENU_INGESTION_BASE_URL env var.');
  process.exit(1);
}
if (!orderBaseUrl) {
  console.error('Missing ORDER_SERVICE_BASE_URL env var.');
  process.exit(1);
}

const ingestBase = ingestBaseUrl.replace(/\/$/, '');
const orderBase = orderBaseUrl.replace(/\/$/, '');
const token = getIdentityToken(ingestBase);

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
  const menuPayload = {
    storeId,
    jobId: `job-${suffix}-${Date.now()}`,
    menu: {
      items: [
        {
          id: 'ci-menu-item',
          name: 'CI Menu Item',
          priceCents: 1234,
          available: true,
          category: 'CI'
        }
      ]
    }
  };

  const { res: ingestRes, data: ingestData } = await fetchJson(`${ingestBase}/internal/test/menu-update`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`
    },
    body: JSON.stringify(menuPayload)
  });
  assertOk('menu ingest', ingestRes, ingestData);

  const { res: menuRes, data: menuData } = await fetchJson(`${orderBase}/stores/${encodeURIComponent(storeId)}/menu`, {
    method: 'GET'
  });
  assertOk('menu fetch', menuRes, menuData);
  const items = Array.isArray(menuData?.items) ? menuData.items : [];
  const found = items.find((item) => item?.id === 'ci-menu-item');
  if (!found) {
    throw new Error('menu item not found after ingest');
  }

  console.log('✓ menu ingest e2e ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
