import { getIdentityToken } from './lib/gcloud_tokens.mjs';
import { patchFirestoreDoc } from './lib/firestore_admin.mjs';

const DEFAULT_TIMEOUT_MS = 20000;
const paymentsBaseUrl = process.env.PAYMENTS_SERVICE_BASE_URL;
const orderBaseUrl = process.env.ORDER_SERVICE_BASE_URL;
const projectId = process.env.FIREBASE_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT || '';
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const tenantId = `test-tenant-${suffix}`;
const storeId = `test-store-${suffix}`;
const customerId = `test-customer-${suffix}`;

if (!paymentsBaseUrl) {
  console.error('Missing PAYMENTS_SERVICE_BASE_URL env var.');
  process.exit(1);
}
if (!orderBaseUrl) {
  console.error('Missing ORDER_SERVICE_BASE_URL env var.');
  process.exit(1);
}
if (!projectId) {
  console.error('Missing FIREBASE_PROJECT_ID env var.');
  process.exit(1);
}

const paymentsApi = paymentsBaseUrl.replace(/\/$/, '');
const orderApi = orderBaseUrl.replace(/\/$/, '');

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
  const orderToken = getIdentityToken(orderApi);

  const { res: orderRes, data: order } = await fetchJson(`${orderApi}/orders`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${orderToken}` },
    body: JSON.stringify({
      storeId,
      tenantId,
      customerId,
      channel: 'webapp',
      callSid: `ci-refund-${Date.now()}`,
      customerName: 'CI Refund',
      callerId: '+33123456789',
      businessType: 'restaurant',
      paymentMethod: 'card',
      fulfillmentType: 'pickup',
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
  assertOk('create order', orderRes, order);
  if (!order?.id) {
    throw new Error('order response missing id');
  }

  const { res: paymentRes, data: paymentData } = await fetchJson(
    `${paymentsApi}/orders/${order.id}/payment-intent`,
    {
      method: 'POST',
      body: JSON.stringify({
        customerId,
        customerName: 'CI Refund',
        amountCents: 1200,
        currency: 'eur',
        sessionId: `ci-${Date.now()}`
      })
    }
  );
  assertOk('payment intent', paymentRes, paymentData);
  if (!paymentData?.paymentId || !paymentData?.paymentIntentId) {
    throw new Error('payment intent missing ids');
  }

  await patchFirestoreDoc({
    projectId,
    documentPath: `orders/${order.id}/payments/${paymentData.paymentId}`,
    fields: {
      status: 'requires_capture',
      stripePaymentIntentId: paymentData.paymentIntentId,
      amountCents: 1200
    }
  });

  const { res: refundRes, data: refundData } = await fetchJson(
    `${paymentsApi}/orders/${order.id}/refund`,
    {
      method: 'POST',
      body: JSON.stringify({ reason: 'requested_by_customer' })
    }
  );
  assertOk('refund', refundRes, refundData);
  if (refundData?.refundType !== 'void') {
    throw new Error(`unexpected refund type: ${JSON.stringify(refundData)}`);
  }
  console.log('✓ refund flow ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
