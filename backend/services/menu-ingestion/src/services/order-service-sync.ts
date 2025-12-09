import type { DraftMenu, MenuItem } from '../types.js';

interface OrderServiceMenuItem {
  id: string;
  name: string;
  priceCents: number;
  available: boolean;
  category: string;
  modifiers: Array<{ name: string; priceCents: number }>;
  description: string;
}

interface OrderServiceMenuRecord {
  storeId: string;
  items: OrderServiceMenuItem[];
  updatedAt: Date;
}

export function mapDraftItemsToOrderServiceMenu(draft: DraftMenu): OrderServiceMenuRecord {
  const items: OrderServiceMenuItem[] = draft.items.map((item) => toOrderServiceItem(item));
  return {
    storeId: draft.restaurantId,
    items,
    updatedAt: new Date(),
  };
}

function toOrderServiceItem(item: MenuItem): OrderServiceMenuItem {
  const price = item.price ?? 0;
  const modifiers =
    (item.sizes ?? []).map((s) => ({
      name: s,
      priceCents: 0,
    })) ?? [];
  const allergyNote =
    item.allergens && item.allergens.length
      ? `Allergens: ${item.allergens.join(', ')}`
      : '';
  return {
    id: item.id || safeId(item.name),
    name: item.name,
    priceCents: Math.round(price * 100),
    available: item.available ?? true,
    category: item.category || 'uncategorized',
    modifiers,
    description: allergyNote,
  };
}

function safeId(name: string): string {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '') || `item-${Date.now()}`;
}
