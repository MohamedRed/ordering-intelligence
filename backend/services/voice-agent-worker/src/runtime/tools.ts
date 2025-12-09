import { llm } from '@livekit/agents';
import type { ToolConfig } from '@ordering-intelligence/voice-agent-config';
import { z } from 'zod';

import { OrderState, formatOrderSummary } from './order-state';
import { findMenuItem, type MenuSnapshot } from './menu';

const payloadSchema = z.object({
  payload: z
    .record(z.any())
    .optional()
    .describe('Arbitrary payload forwarded to the downstream integration'),
});

const addItemSchema = z.object({
  itemId: z.string().optional().describe('Menu item ID if known'),
  name: z.string().optional().describe('Human-readable item name (e.g., "Big Mac Combo")'),
  size: z.string().optional().describe('Size code if the item has multiple sizes'),
  price: z.number().optional().describe('Price of the item in local currency'),
  details: z.record(z.any()).optional().describe('Optional structured details (size, sauce, etc.)'),
});

const removeItemSchema = z.object({
  orderIds: z
    .array(z.string())
    .nonempty()
    .describe('Order IDs previously returned by list_items or add_item'),
});

export interface ToolContextOptions {
  onCompleteOrder?: (summary: { totalPrice: number; items: ReturnType<OrderState['list']> }) => Promise<void>;
}

export function createToolContext(
  tools: ToolConfig[],
  orderState: OrderState,
  options: ToolContextOptions = {},
  menu?: MenuSnapshot,
): llm.ToolContext | undefined {
  if (tools.length === 0) {
    return undefined;
  }

  const context: llm.ToolContext = {};

  // Pass-through HTTP tools from presets (unchanged behaviour)
  tools.forEach((tool) => {
    context[tool.name] = llm.tool({
      description: tool.description ?? 'HTTP integration invoked by the agent.',
      parameters: payloadSchema,
      execute: async ({ payload }) => {
        const method = (tool.invoke.method ?? 'POST').toUpperCase();
        const headers = {
          'Content-Type': 'application/json',
          ...(tool.invoke.headers ?? {}),
        };

        const body = method === 'GET' ? undefined : JSON.stringify(payload ?? {});
        const response = await fetch(tool.invoke.url, { method, headers, body });

        const text = await response.text();
        if (!response.ok) {
          throw new Error(`Tool ${tool.name} responded with ${response.status}: ${text}`);
        }

        try {
          return JSON.parse(text);
        } catch {
          return text;
        }
      },
    });
  });

  // Built-in lightweight order state tools to mirror the drive-thru flow.
  context['order_state.add_item'] = llm.tool({
    description:
      'Add a single item to the in-memory order. Use for every confirmed item so list/remove/checkout stay accurate.',
    parameters: addItemSchema,
    execute: async ({ itemId, name, size, price, details }) => {
      const resolved = resolveMenuItem(menu, itemId ?? name, size);
      if (!resolved && !(name ?? itemId)) {
        throw new Error('Item name or id is required to add an item.');
      }

      const itemName = resolved?.name ?? name ?? itemId!;
      const itemPrice = typeof price === 'number' ? price : resolved?.price;
      const finalDetails = { ...(details ?? {}), size: size ?? resolved?.sizes?.[0] };

      if (!resolved && menu) {
        throw new Error('Unknown item for this menu. Please ask the customer to pick an item from the menu.');
      }

      const item = orderState.add(itemName, itemPrice, finalDetails);
      return {
        message: `Item added: ${item.name}`,
        orderId: item.orderId,
        price: item.price ?? null,
        details: item.details ?? {},
      };
    },
  });

  context['order_state.list_items'] = llm.tool({
    description: 'List the current items in the in-memory order with totals.',
    parameters: z.object({}),
    execute: async () => {
      const summary = formatOrderSummary(orderState);
      return {
        totalPrice: summary.totalPrice,
        itemCount: summary.items.length,
        items: summary.items,
      };
    },
  });

  context['order_state.remove_items'] = llm.tool({
    description: 'Remove one or more items from the in-memory order by orderId.',
    parameters: removeItemSchema,
    execute: async ({ orderIds }) => {
      const removed: string[] = [];
      const missing: string[] = [];

      orderIds.forEach((id) => {
        const item = orderState.remove(id);
        if (item) {
          removed.push(id);
        } else {
          missing.push(id);
        }
      });

      return {
        removed,
        missing,
        itemCount: orderState.list().length,
      };
    },
  });

  context['order_state.complete_order'] = llm.tool({
    description:
      'Call this when the customer confirms the order. Returns total and triggers checkout notifications.',
    parameters: z.object({}),
    execute: async () => {
      const summary = formatOrderSummary(orderState);
      if (summary.items.length === 0) {
        return { error: 'Cannot complete order because it is empty.' };
      }

      await options.onCompleteOrder?.({ totalPrice: summary.totalPrice, items: summary.items });

      return {
        message: `Order completed. Total: ${summary.totalPrice.toFixed(2)}.`,
        totalPrice: summary.totalPrice,
        itemCount: summary.items.length,
      };
    },
  });

  return context;
}

function resolveMenuItem(menu: MenuSnapshot | undefined, idOrName?: string, size?: string) {
  if (!idOrName) return undefined;
  return findMenuItem(menu, idOrName, size);
}
