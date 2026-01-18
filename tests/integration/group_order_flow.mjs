import { getIdentityToken } from './lib/gcloud_tokens.mjs';

const DEFAULT_TIMEOUT_MS = 20000;
const baseUrl = process.env.ORDER_SERVICE_BASE_URL;
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const storeId = `test-store-${suffix}`;
const tenantId = `test-tenant-${suffix}`;
const customerId = `test-customer-${suffix}`;

if (!baseUrl) {
  console.error('Missing ORDER_SERVICE_BASE_URL env var.');
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
  if (!(res.status >= 200 && res.status < 300)) {
    const payload = data ? JSON.stringify(data) : 'no body';
    throw new Error(`${label} failed: ${res.status} ${payload}`);
  }
};

const run = async () => {
  const token = getIdentityToken(apiBase);
  const authHeader = { Authorization: `Bearer ${token}` };

  const { res: createRes, data: createData } = await fetchJson(`${apiBase}/group_orders`, {
    method: 'POST',
    headers: authHeader,
    body: JSON.stringify({
      tenantId,
      storeId,
      customerId,
      fulfillmentType: 'pickup',
      paymentMode: 'single_payer',
      paymentMethod: 'cash',
      host: {
        channel: 'webapp',
        userId: `test-user-${suffix}`,
        displayName: 'CI Host',
      },
      participantId: `test-user-${suffix}`,
      displayName: 'CI Host',
    }),
  });
  assertOk('create group order', createRes, createData);
  const groupOrder = createData?.groupOrder;
  if (!groupOrder?.id) {
    throw new Error('group order response missing id');
  }
  console.log(`✓ group order created (${groupOrder.id})`);

  const { res: itemsRes, data: itemsData } = await fetchJson(`${apiBase}/group_orders/${groupOrder.id}/items`, {
    method: 'POST',
    headers: authHeader,
    body: JSON.stringify({
      participantId: `test-user-${suffix}`,
      items: [
        {
          itemId: 'test-pizza',
          name: 'Test Pizza',
          quantity: 1,
          priceCents: 1200,
          category: 'Pizza',
          modifiers: [],
        },
      ],
    }),
  });
  assertOk('add group items', itemsRes, itemsData);
  console.log('✓ group items added');

  const { res: lockRes, data: lockData } = await fetchJson(`${apiBase}/group_orders/${groupOrder.id}/lock`, {
    method: 'POST',
    headers: authHeader,
    body: JSON.stringify({ taxCents: 0, feeCents: 0, discountCents: 0 }),
  });
  assertOk('lock group order', lockRes, lockData);
  console.log('✓ group order locked');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
