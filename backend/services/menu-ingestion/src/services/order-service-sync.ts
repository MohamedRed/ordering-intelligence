import type { BundleRule, DraftMenu, MenuItem, ModifierGroup } from '../types.js';

interface OrderServiceMenuItem {
  id: string;
  name: string;
  priceCents: number;
  available: boolean;
  category: string;
  modifiers: Array<{ name: string; priceCents: number }>;
  modifierGroups?: Array<{
    id: string;
    name: string;
    required: boolean;
    minSelections: number;
    maxSelections: number;
    options: Array<{ id: string; name: string; priceCents: number }>;
  }>;
  description: string;
}

interface OrderServiceBundleComponent {
  role: string;
  itemIds?: string[];
  category?: string;
  requiredGroupIds?: string[];
}

interface OrderServiceBundleRule {
  bundleId: string;
  displayName: string;
  triggerItemId?: string;
  triggerCategory?: string;
  components: OrderServiceBundleComponent[];
  promptHintsFr?: string;
}

interface OrderServiceMenuRecord {
  storeId: string;
  items: OrderServiceMenuItem[];
  bundleRules?: OrderServiceBundleRule[];
  updatedAt: Date;
}

export function mapDraftItemsToOrderServiceMenu(draft: DraftMenu): OrderServiceMenuRecord {
  const items: OrderServiceMenuItem[] = draft.items.map((item) => toOrderServiceItem(item));
  return {
    storeId: draft.restaurantId,
    items,
    bundleRules: draft.bundleRules?.length ? draft.bundleRules.map(toOrderServiceBundleRule) : undefined,
    updatedAt: new Date(),
  };
}

function toOrderServiceItem(item: MenuItem): OrderServiceMenuItem {
  const price = item.price ?? 0;
  const sizes = item.sizes ?? [];
  const modifierLabels = [
    ...(item.modifiers ?? []).map((m) => String(m ?? '').trim()).filter(Boolean),
    ...sizes.map((s) => String(s ?? '').trim()).filter(Boolean),
  ];
  const seen = new Set<string>();
  const modifiers = modifierLabels
    .filter((m) => {
      const key = m.toLowerCase();
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .map((name) => ({ name, priceCents: 0 }));

  const baseGroups = (item.modifierGroups ?? []).filter(Boolean);
  const shouldAskSize = sizes.length >= 2;
  const hasSizeGroup = baseGroups.some((g) => String((g as any)?.id ?? '').toLowerCase() === 'size');
  const derivedSizeGroup: ModifierGroup | null =
    shouldAskSize && !hasSizeGroup
      ? {
          id: 'size',
          name: 'Size',
          required: true,
          minSelections: 1,
          maxSelections: 1,
          options: sizes.map((s) => ({
            id: safeId(String(s ?? '')),
            name: String(s ?? ''),
            priceCents: 0,
          })),
        }
      : null;
  const modifierGroups =
    baseGroups.length || derivedSizeGroup
      ? [...baseGroups, ...(derivedSizeGroup ? [derivedSizeGroup] : [])].map((g) => ({
          id: String(g.id ?? '').trim(),
          name: String(g.name ?? '').trim(),
          required: Boolean((g as any).required),
          minSelections: Number.isFinite(Number((g as any).minSelections)) ? Number((g as any).minSelections) : 0,
          maxSelections: Number.isFinite(Number((g as any).maxSelections)) ? Number((g as any).maxSelections) : 0,
          options: Array.isArray((g as any).options)
            ? (g as any).options.map((o: any) => ({
                id: String(o?.id ?? '').trim(),
                name: String(o?.name ?? '').trim(),
                priceCents: Number.isFinite(Number(o?.priceCents)) ? Number(o.priceCents) : 0,
              }))
            : [],
        }))
      : undefined;
  const allergyNote =
    item.allergens && item.allergens.length
      ? `Allergens: ${item.allergens.join(', ')}`
      : '';
  const descriptionParts = [
    String(item.description ?? '').trim(),
    allergyNote,
  ].filter(Boolean);
  return {
    id: (item.id || '').trim() || safeId(item.name),
    name: item.name,
    priceCents: Math.round(price * 100),
    available: item.available ?? true,
    category: item.category || 'uncategorized',
    modifiers,
    modifierGroups,
    description: descriptionParts.join(' • '),
  };
}

function safeId(name: string): string {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '') || `item-${Date.now()}`;
}

function toOrderServiceBundleRule(rule: BundleRule): OrderServiceBundleRule {
  return {
    bundleId: String(rule.bundleId ?? '').trim(),
    displayName: String(rule.displayName ?? '').trim(),
    triggerItemId: rule.triggerItemId ? String(rule.triggerItemId).trim() : undefined,
    triggerCategory: rule.triggerCategory ? String(rule.triggerCategory).trim() : undefined,
    components: (rule.components ?? []).map((c) => ({
      role: String((c as any).role ?? '').trim(),
      itemIds: Array.isArray((c as any).itemIds) ? (c as any).itemIds.map((id: any) => String(id).trim()).filter(Boolean) : undefined,
      category: (c as any).category ? String((c as any).category).trim() : undefined,
      requiredGroupIds: Array.isArray((c as any).requiredGroupIds)
        ? (c as any).requiredGroupIds.map((id: any) => String(id).trim()).filter(Boolean)
        : undefined,
    })),
    promptHintsFr: rule.promptHintsFr ? String(rule.promptHintsFr) : undefined,
  };
}
