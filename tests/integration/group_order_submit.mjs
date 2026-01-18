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
        userId: `test-host-${suffix}`,
        displayName: 'CI Host'
      },
      participantId: `test-host-${suffix}`,
      displayName: 'CI Host'
    })
  });
  assertOk('create group order', createRes, createData);
  const groupOrder = createData?.groupOrder;
  if (!groupOrder?.id) {
    throw new Error('group order response missing id');
  }

  const { res: inviteRes, data: inviteData } = await fetchJson(
    `${apiBase}/group_orders/${groupOrder.id}/invites`,
    {
      method: 'POST',
      headers: authHeader,
      body: JSON.stringify({
        participantId: `test-host-${suffix}`,
        maxUses: 2
      })
    }
  );
  assertOk('create invite', inviteRes, inviteData);
  const inviteId = inviteData?.invite?.inviteId;
  if (!inviteId) {
    throw new Error('invite response missing inviteId');
  }

  const { res: joinRes, data: joinData } = await fetchJson(
    `${apiBase}/group_orders/${groupOrder.id}/join`,
    {
      method: 'POST',
      headers: authHeader,
      body: JSON.stringify({
        participantId: `test-guest-${suffix}`,
        displayName: 'CI Guest',
        inviteId
      })
    }
  );
  assertOk('join group order', joinRes, joinData);

  const { res: itemsRes } = await fetchJson(`${apiBase}/group_orders/${groupOrder.id}/items`, {
    method: 'POST',
    headers: authHeader,
    body: JSON.stringify({
      participantId: `test-host-${suffix}`,
      items: [
        {
          itemId: 'test-pizza',
          name: 'Test Pizza',
          quantity: 1,
          priceCents: 1200,
          category: 'Pizza',
          modifiers: []
        }
      ]
    })
  });
  assertOk('add host items', itemsRes, null);

  const { res: lockRes } = await fetchJson(`${apiBase}/group_orders/${groupOrder.id}/lock`, {
    method: 'POST',
    headers: authHeader,
    body: JSON.stringify({ taxCents: 0, feeCents: 0, discountCents: 0 })
  });
  assertOk('lock group order', lockRes, null);

  const { res: submitRes, data: submitData } = await fetchJson(
    `${apiBase}/group_orders/${groupOrder.id}/submit`,
    {
      method: 'POST',
      headers: authHeader,
      body: JSON.stringify({})
    }
  );
  assertOk('submit group order', submitRes, submitData);
  const submitted = submitData?.groupOrder;
  if (!submitted?.orderId) {
    throw new Error('group order submit missing orderId');
  }

  const { res: orderRes, data: orderData } = await fetchJson(`${apiBase}/orders/${submitted.orderId}`, {
    method: 'GET',
    headers: authHeader
  });
  assertOk('fetch submitted order', orderRes, orderData);
  console.log('✓ group order submit ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
