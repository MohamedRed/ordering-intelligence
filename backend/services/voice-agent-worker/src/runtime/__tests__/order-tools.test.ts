import assert from 'node:assert/strict';
import test from 'node:test';

import { OrderState } from '../order-state';
import { createToolContext } from '../tools';

function buildContext(onComplete?: () => void) {
  const orderState = new OrderState();
  let completeCalled = false;

  const toolContext = createToolContext(
    [
      {
        name: 'noop.remote',
        invoke: { url: 'http://example.com/tools/noop', method: 'POST' },
      },
    ],
    orderState,
    {
      onCompleteOrder: async () => {
        completeCalled = true;
        onComplete?.();
      },
    },
  )!;

  return { toolContext, orderState, getCompleteCalled: () => completeCalled };
}

test('complete_order rejects empty cart', async () => {
  const { toolContext } = buildContext();
  const result = await toolContext['order_state.complete_order'].execute({});
  assert.equal(result.error, 'Cannot complete order because it is empty.');
});

test('remove_items reports missing ids', async () => {
  const { toolContext } = buildContext();
  const result = await toolContext['order_state.remove_items'].execute({ orderIds: ['abc'] });
  assert.deepEqual(result.missing, ['abc']);
  assert.equal(result.itemCount, 0);
});

test('complete_order returns total and triggers hook', async () => {
  const { toolContext, getCompleteCalled } = buildContext();

  await toolContext['order_state.add_item'].execute({ name: 'Burger', price: 10 });
  const result = await toolContext['order_state.complete_order'].execute({});

  assert.equal(result.totalPrice, 10);
  assert.equal(result.itemCount, 1);
  assert.ok(getCompleteCalled());
});
