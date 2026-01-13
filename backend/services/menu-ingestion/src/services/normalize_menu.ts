import { ANALYSIS_MODEL } from '../config.js';
import type { BundleRule, MenuItem, ModifierGroup, ModifierOption } from '../types.js';
import { slugifyName } from '../utils.js';
import { geminiJsonText } from './generation.js';

export type NormalizedMenuResult = {
  items: MenuItem[];
  bundleRules: BundleRule[];
  issues: string[];
};

function safeId(input: string): string {
  const s = slugifyName(input || '');
  return s || `id-${Date.now()}`;
}

function deriveSizeGroupFromSizes(sizes: string[]): ModifierGroup | null {
  const clean = (sizes ?? []).map((s) => String(s || '').trim()).filter(Boolean);
  if (clean.length < 2) return null; // only ask when multiple sizes exist
  const options: ModifierOption[] = clean.map((name) => ({
    id: safeId(name),
    name,
    priceCents: 0,
  }));
  return {
    id: 'size',
    name: 'Size',
    required: true,
    minSelections: 1,
    maxSelections: 1,
    options,
  };
}

function normalizeModifierGroups(groups: any, issues: string[], itemId: string): ModifierGroup[] {
  if (!Array.isArray(groups)) return [];
  const out: ModifierGroup[] = [];
  for (const g of groups) {
    if (!g || typeof g !== 'object') continue;
    const name = String(g.name ?? '').trim();
    const id = String(g.id ?? '').trim() || safeId(name);
    const required = Boolean(g.required ?? false);
    const minSelections = Number.isFinite(Number(g.minSelections)) ? Number(g.minSelections) : 0;
    const maxSelections = Number.isFinite(Number(g.maxSelections)) ? Number(g.maxSelections) : 0;
    const rawOptions = Array.isArray(g.options) ? g.options : [];
    const options: ModifierOption[] = [];
    const seen = new Set<string>();
    for (const o of rawOptions) {
      if (!o || typeof o !== 'object') continue;
      const oname = String(o.name ?? '').trim();
      if (!oname) continue;
      let oid = String(o.id ?? '').trim() || safeId(oname);
      while (seen.has(oid)) oid = `${oid}-${options.length + 1}`;
      seen.add(oid);
      const priceCents = Number.isFinite(Number(o.priceCents)) ? Number(o.priceCents) : 0;
      options.push({ id: oid, name: oname, priceCents });
    }
    if (!name || !options.length) continue;
    let min = Math.max(0, minSelections);
    let max = Math.max(0, maxSelections);
    if (required && min === 0) min = 1;
    if (max === 0) max = options.length;
    if (max < min) max = min;
    if (max > options.length) max = options.length;
    out.push({ id, name, required, minSelections: min, maxSelections: max, options });
  }
  if (out.some((g) => g.id === '')) issues.push(`item:${itemId} had modifier group with empty id`);
  return out;
}

function normalizeBundleRules(raw: any, itemsById: Map<string, MenuItem>, groupIds: Set<string>, issues: string[]): BundleRule[] {
  if (!Array.isArray(raw)) return [];
  const out: BundleRule[] = [];
  for (const r of raw) {
    if (!r || typeof r !== 'object') continue;
    const displayName = String(r.displayName ?? '').trim();
    const bundleId = String(r.bundleId ?? '').trim() || safeId(displayName || 'bundle');
    const triggerItemId = String(r.triggerItemId ?? '').trim();
    const triggerCategory = String(r.triggerCategory ?? '').trim();
    const componentsRaw = Array.isArray(r.components) ? r.components : [];
    const promptHintsFr = String(r.promptHintsFr ?? '').trim() || undefined;

    if (!displayName) continue;
    const validTriggerItemId = triggerItemId && itemsById.has(triggerItemId) ? triggerItemId : '';
    if (triggerItemId && !validTriggerItemId) {
      issues.push(`bundle:${bundleId} triggerItemId not found: ${triggerItemId}`);
    }
    if (!validTriggerItemId && !triggerCategory) continue;

    const components: any[] = [];
    for (const c of componentsRaw) {
      if (!c || typeof c !== 'object') continue;
      const role = String(c.role ?? '').trim();
      if (!role) continue;
      const itemIds: string[] = Array.isArray(c.itemIds)
        ? (c.itemIds as any[]).map((v: any) => String(v ?? '').trim()).filter((v) => v.length > 0)
        : [];
      const category = String(c.category ?? '').trim() || undefined;
      const filteredItemIds = itemIds.filter((id: string) => itemsById.has(id));
      if (filteredItemIds.length !== itemIds.length) {
        const missing = itemIds.filter((id: string) => !itemsById.has(id));
        if (missing.length) issues.push(`bundle:${bundleId} component:${role} unknown itemIds: ${missing.join(',')}`);
      }
      const requiredGroupIds: string[] = Array.isArray(c.requiredGroupIds)
        ? (c.requiredGroupIds as any[]).map((v: any) => String(v ?? '').trim()).filter((v) => v.length > 0)
        : [];
      const filteredGroupIds = requiredGroupIds.filter((gid: string) => groupIds.has(gid));
      if (filteredGroupIds.length !== requiredGroupIds.length) {
        const missing = requiredGroupIds.filter((gid: string) => !groupIds.has(gid));
        if (missing.length) issues.push(`bundle:${bundleId} component:${role} unknown requiredGroupIds: ${missing.join(',')}`);
      }
      if (!filteredItemIds.length && !category) continue;
      components.push({
        role,
        ...(filteredItemIds.length ? { itemIds: filteredItemIds } : {}),
        ...(category ? { category } : {}),
        ...(filteredGroupIds.length ? { requiredGroupIds: filteredGroupIds } : {}),
      });
    }
    if (!components.length) continue;
    out.push({
      bundleId,
      displayName,
      ...(validTriggerItemId ? { triggerItemId: validTriggerItemId } : {}),
      ...(triggerCategory ? { triggerCategory } : {}),
      components,
      ...(promptHintsFr ? { promptHintsFr } : {}),
    });
  }
  return out;
}

export async function normalizeMenuStructure(params: {
  restaurantId: string;
  items: MenuItem[];
}): Promise<NormalizedMenuResult> {
  const issues: string[] = [];
  const baseItems = params.items.map((it) => ({ ...it }));
  const itemsById = new Map<string, MenuItem>();
  for (const it of baseItems) {
    const id = String(it.id ?? '').trim() || safeId(it.name);
    it.id = id;
    itemsById.set(id, it);
  }

  // Prompt stage-B: suggest modifierGroups/bundleRules based on extracted fields.
  // This is text-only and should be fast (no composite/image model).
  const prompt =
    'You are normalizing a restaurant menu for a voice ordering agent.\n' +
    'You MUST NOT create new menu items. Only use the existing item ids given.\n' +
    'You MAY create modifierGroups on items and bundleRules at the menu level.\n' +
    '\n' +
    'Input items JSON:\n' +
    JSON.stringify(
      baseItems.map((i) => ({
        id: i.id,
        name: i.name,
        category: i.category ?? '',
        description: i.description ?? '',
        price: i.price ?? null,
        currency: i.currency ?? '',
        sizes: i.sizes ?? [],
        modifiers: i.modifiers ?? [],
      }))
    ) +
    '\n' +
    '\n' +
    'Return STRICT JSON with shape:\n' +
    '{\n' +
    '  "items": [ { "id": string, "modifierGroups": [ { "id": string, "name": string, "required": boolean, "minSelections": number, "maxSelections": number, "options": [ { "id": string, "name": string, "priceCents": number } ] } ] } ],\n' +
    '  "bundleRules": [ { "bundleId": string, "displayName": string, "triggerItemId"?: string, "triggerCategory"?: string, "components": [ { "role": string, "itemIds"?: string[], "category"?: string, "requiredGroupIds"?: string[] } ], "promptHintsFr"?: string } ]\n' +
    '}\n' +
    '\n' +
    'Rules:\n' +
    '- If an item has multiple sizes, create a required modifier group "Size" (min=1,max=1).\n' +
    '- Only reference itemIds that exist in the input.\n' +
    '- If unsure, omit bundleRules.\n' +
    '- Output JSON only.';

  let modelOut: any;
  try {
    modelOut = await geminiJsonText(prompt, ANALYSIS_MODEL, 'normalize-menu');
  } catch (err) {
    issues.push(`normalize_menu_failed:${(err as Error).message}`);
    modelOut = undefined;
  }

  // Apply model output onto base items, but validate strictly.
  const outItems = baseItems.map((it) => ({ ...it }));
  const outById = new Map<string, MenuItem>();
  for (const it of outItems) outById.set(it.id, it);

  if (modelOut && typeof modelOut === 'object') {
    const rawItems = Array.isArray(modelOut.items) ? modelOut.items : [];
    for (const ri of rawItems) {
      if (!ri || typeof ri !== 'object') continue;
      const id = String(ri.id ?? '').trim();
      if (!id || !outById.has(id)) continue;
      const tgt = outById.get(id)!;
      const normalizedGroups = normalizeModifierGroups(ri.modifierGroups, issues, id);
      if (normalizedGroups.length) {
        tgt.modifierGroups = normalizedGroups;
      }
    }
  }

  // Ensure size rule for items without modifierGroups.
  for (const it of outItems) {
    if (Array.isArray(it.modifierGroups) && it.modifierGroups.length) continue;
    const g = deriveSizeGroupFromSizes(it.sizes ?? []);
    if (g) it.modifierGroups = [g];
  }

  // Build a set of all group ids for bundleRules validation.
  const groupIds = new Set<string>();
  for (const it of outItems) {
    for (const g of it.modifierGroups ?? []) {
      if (g?.id) groupIds.add(g.id);
    }
  }

  const bundleRules = normalizeBundleRules(modelOut?.bundleRules, outById, groupIds, issues);

  return { items: outItems, bundleRules, issues };
}
