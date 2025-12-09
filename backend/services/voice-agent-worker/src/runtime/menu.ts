type MenuSize = 'S' | 'M' | 'L' | string;

export interface MenuItem {
  id: string;
  name: string;
  priceCents?: number;
  category?: string;
  sizes?: MenuSize[];
  available?: boolean;
  modifiers?: string[];
}

export interface MenuSnapshot {
  storeId?: string;
  updated?: string;
  items: MenuItem[];
}

export async function fetchMenuSnapshot(orderServiceUrl?: string, explicitStoreId?: string): Promise<MenuSnapshot | undefined> {
  if (!orderServiceUrl) {
    return undefined;
  }

  const storeId = explicitStoreId || process.env.STORE_ID || 'demo-store';
  const endpoint = `${orderServiceUrl.replace(/\/$/, '')}/stores/${storeId}/menu/snapshot`;

  try {
    const response = await fetch(endpoint, {
      method: 'GET',
      headers: { 'Content-Type': 'application/json' },
    });

    if (!response.ok) {
      console.warn('voice-agent-worker:menu_fetch_failed', { status: response.status, endpoint });
      return undefined;
    }

    const data = (await response.json()) as { items?: MenuItem[] };
    if (!data?.items || !Array.isArray(data.items)) {
      console.warn('voice-agent-worker:menu_fetch_invalid_shape', { endpoint });
      return undefined;
    }

    return { ...data, items: data.items };
  } catch (error) {
    console.warn('voice-agent-worker:menu_fetch_error', { error, endpoint });
    return undefined;
  }
}

export function formatMenuInstructions(snapshot?: MenuSnapshot): string | undefined {
  if (!snapshot || snapshot.items.length === 0) {
    return undefined;
  }

  const header = snapshot.storeId ? `Store: ${snapshot.storeId}` : undefined;
  const updated = snapshot.updated ? `Updated: ${snapshot.updated}` : undefined;

  const lines = snapshot.items.slice(0, 120).map((item) => {
    const sizes = item.sizes?.length ? ` sizes: ${item.sizes.join('/')}` : '';
    const price =
      typeof item.priceCents === 'number' ? ` $${(item.priceCents / 100).toFixed(2)}` : '';
    const availability = item.available === false ? ' (UNAVAILABLE)' : '';
    const mods = item.modifiers?.length ? ` mods: ${item.modifiers.join(', ')}` : '';
    const category = item.category ? ` category: ${item.category}` : '';
    return `- ${item.name} (id: ${item.id}${sizes}${price}${category}${availability})${mods}`;
  });

  return ['# Menu (snapshot)', ...(header ? [header] : []), ...(updated ? [updated] : []), ...lines].join('\n');
}

export function findMenuItem(snapshot: MenuSnapshot | undefined, idOrName: string, size?: string): MenuItem | undefined {
  if (!snapshot) return undefined;
  const lowered = idOrName.toLowerCase();
  return snapshot.items.find((item) => {
    const matchesId = item.id.toLowerCase() === lowered;
    const matchesName = item.name.toLowerCase() === lowered;
    const sizeOk = !size || !item.sizes?.length || item.sizes.includes(size);
    return (matchesId || matchesName) && sizeOk;
  });
}
