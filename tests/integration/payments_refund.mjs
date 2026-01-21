import { getIdentityToken } from './lib/gcloud_tokens.mjs';
import { patchFirestoreDoc } from './lib/firestore_admin.mjs';
import { assertOk, fetchJson, requestWithRetry } from './lib/payments_test_utils.mjs';

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

const run = async () => {
  const orderToken = getIdentityToken(orderApi);

  const { res: orderRes, data: order } = await fetchJson(`${orderApi}/orders`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${orderToken}`,
      'Content-Type': 'application/json',
    },
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

  const { data: paymentData } = await requestWithRetry(
    'payment intent',
    () =>
    fetchJson(`${paymentsApi}/orders/${order.id}/payment-intent`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        customerId,
        customerName: 'CI Refund',
        amountCents: 1200,
        currency: 'eur',
        sessionId: `ci-${Date.now()}`
      })
    }),
    { healthCheckUrl: paymentsApi }
  );
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

  const { data: refundData } = await requestWithRetry(
    'refund',
    () =>
    fetchJson(`${paymentsApi}/orders/${order.id}/refund`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ reason: 'requested_by_customer' })
    }),
    { healthCheckUrl: paymentsApi }
  );
  if (refundData?.refundType !== 'void') {
    throw new Error(`unexpected refund type: ${JSON.stringify(refundData)}`);
  }
  console.log('✓ refund flow ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
