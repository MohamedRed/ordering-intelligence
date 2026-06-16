import { bucketEnv as BUCKET_ENV, ANALYSIS_MODEL } from '../config.js';
import type { MenuItem } from '../types.js';
import { slugifyName } from '../utils.js';
import { geminiJson } from './generation.js';
import type { GeminiItemImage } from './ingestion_types.js';
import {
  failWorkflowNode,
  finishWorkflowNode,
  startWorkflowNode,
} from './workflow.js';

const BUCKET = (BUCKET_ENV || '') as string;

export async function assignThumbsToMenu(
  menu: MenuItem[],
  thumbs: GeminiItemImage[],
  jobId?: string,
): Promise<MenuItem[]> {
  const menuJson = menu.length ? JSON.stringify(menu) : undefined;
  const thumbItems: MenuItem[] = [];

  for (const thumb of thumbs) {
    const parsed = await describeThumbWithContext(menuJson, thumb, jobId);
    thumbItems.push(parsedToItem(parsed, thumb));
  }

  if (!menu.length) return thumbItems;
  return mergeMenuWithThumbs(menu, thumbItems);
}

async function describeThumbWithContext(
  menuJson: string | undefined,
  thumb: GeminiItemImage,
  jobId?: string,
): Promise<any> {
  const prompt =
    'You will be given a menu (as JSON) and a thumbnail image of a menu item. ' +
    'Return JSON for the best matching item with fields {id, name, category, price, currency, available}. ' +
    'Prefer ids/names from the provided menu if they match the thumbnail. ' +
    'If no menu is provided, infer from the image only. ' +
    (menuJson ? `Menu JSON: ${menuJson}` : 'No menu JSON provided.');

  try {
    const mime = thumb.storagePath.toLowerCase().endsWith('.png')
      ? 'image/png'
      : thumb.storagePath.toLowerCase().match(/\.jpe?g$/)
        ? 'image/jpeg'
        : 'image/png';
    const parsedName = /^item_(\d+)_(\d+)$/.exec(thumb.name);
    const page = parsedName ? Number(parsedName[1]) : undefined;
    const idx = parsedName ? Number(parsedName[2]) : undefined;
    const nodeId = jobId ? `describe_${thumb.name}` : undefined;
    if (jobId && nodeId) {
      await startWorkflowNode(jobId, {
        id: nodeId,
        parentId: page && idx ? `render_p${page}_i${idx}` : 'root',
        kind: 'describe_thumb',
        label: page && idx ? `Describe item ${idx} (page ${page})` : `Describe ${thumb.name}`,
        modelId: ANALYSIS_MODEL,
        fileUri: `gs://${BUCKET}/${thumb.storagePath}`,
        page,
        itemIndex: idx,
        seq: 5000 + (page ? page * 100 : 0) + (idx ?? 0),
      });
    }
    const resp = await geminiJson(prompt, `gs://${BUCKET}/${thumb.storagePath}`, mime, ANALYSIS_MODEL);
    if (jobId && nodeId) {
      const trimmed: any = resp && typeof resp === 'object' ? {
        id: resp.id,
        name: resp.name,
        category: resp.category,
        price: resp.price,
        currency: resp.currency,
        available: resp.available,
      } : resp;
      await finishWorkflowNode(jobId, nodeId, { meta: { result: trimmed } });
    }
    return resp ?? {};
  } catch (err) {
    console.error('describe-thumb error', err);
    if (jobId) {
      await failWorkflowNode(jobId, `describe_${thumb.name}`, err);
    }
    return {};
  }
}

function parsedToItem(parsed: any, thumb: GeminiItemImage): MenuItem {
  const name = parsed?.name ?? thumb.name ?? 'item';
  const id = parsed?.id ?? slugifyName(name);
  return {
    id,
    name,
    category: parsed?.category ?? undefined,
    price: typeof parsed?.price === 'number' ? parsed.price : undefined,
    currency: parsed?.currency ?? undefined,
    available: parsed?.available ?? true,
    imageUrl: thumb.url,
    photoUrl: thumb.url,
  };
}

function mergeMenuWithThumbs(menu: MenuItem[], thumbs: MenuItem[]): MenuItem[] {
  if (!menu.length) return thumbs;
  const bySlug = new Map<string, MenuItem>();
  for (const m of menu) {
    bySlug.set(slugifyName(m.name), { ...m });
  }

  const used = new Set<string>();
  const merged: MenuItem[] = [];

  for (const t of thumbs) {
    const slug = slugifyName(t.name);
    const base = bySlug.get(slug);
    if (base) {
      merged.push({
        ...base,
        price: base.price ?? t.price,
        currency: base.currency ?? t.currency,
        category: base.category ?? t.category,
        imageUrl: t.imageUrl ?? base.imageUrl,
        photoUrl: t.photoUrl ?? base.photoUrl,
      });
      used.add(slug);
    } else {
      merged.push(t);
    }
  }

  for (const [slug, m] of bySlug.entries()) {
    if (!used.has(slug)) merged.push(m);
  }

  return merged;
}
