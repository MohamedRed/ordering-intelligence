import { Storage } from '@google-cloud/storage';
import { Firestore } from '@google-cloud/firestore';
import { GoogleAuth } from 'google-auth-library';
import {
  bucketEnv as BUCKET_ENV,
  AGENT_ANALYSIS_URL,
  AGENT_COMPOSITE_URL,
  AGENT_BASE_DELAY_MS,
  AGENT_RETRIES,
  ANALYSIS_MODEL,
  COMPOSITE_MODEL,
  RENDER_MODEL,
} from '../config.js';
import { delay, slugifyName, ordinal } from '../utils.js';
import { enqueueAgentJob, waitForAgentJob } from './agent_queue.js';
import { geminiJson, renderImage } from './generation.js';
import {
  failWorkflowNode,
  finishWorkflowNode,
  startWorkflowNode,
} from './workflow.js';
import type { DraftMenu, MenuItem } from '../types.js';

const storage = new Storage();
const firestore = new Firestore({ ignoreUndefinedProperties: true });
const BUCKET = (BUCKET_ENV || "") as string;
const auth = new GoogleAuth({ scopes: 'https://www.googleapis.com/auth/cloud-platform' });

// Cost safeguards
const MAX_PAGES = Number(process.env.MENU_MAX_PAGES ?? 5);
const MAX_ITEMS_PER_PAGE = Number(process.env.MENU_MAX_ITEMS_PER_PAGE ?? 40);
const MAX_TOTAL_ITEMS = Number(process.env.MENU_MAX_TOTAL_ITEMS ?? 120);
const GCS_OP_TIMEOUT_MS = Number(process.env.GCS_OP_TIMEOUT_MS ?? 30_000);

export type GeneratedComposite = { generatedFiles: string[] };
export type ExtractedItems = { images: GeminiItemImage[]; count: number };
export type GeminiItemImage = { name: string; url: string; storagePath: string };
type GradioResult = { text?: string; inlineData?: string; url?: string };

async function withTimeout<T>(promise: Promise<T>, ms: number, label: string): Promise<T> {
  let timeout: NodeJS.Timeout;
  const wrapped = new Promise<never>((_, reject) => {
    timeout = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
  });
  try {
    return await Promise.race([promise, wrapped]);
  } finally {
    clearTimeout(timeout!);
  }
}

export async function analyzeMenuFromOriginal(files: string[], jobId?: string): Promise<MenuItem[]> {
  const results: MenuItem[] = [];
  let page = 0;
  for (const object of files) {
    page += 1;
    const fileUri = `gs://${BUCKET}/${object}`;
    const nodeId = jobId ? `analysis_p${page}` : undefined;
    if (jobId && nodeId) {
      await startWorkflowNode(jobId, {
        id: nodeId,
        parentId: 'root',
        kind: 'analysis',
        label: `Analyze page ${page}`,
        modelId: ANALYSIS_MODEL,
        fileUri,
        page,
        seq: 1000 + page,
      });
    }
    let parsed = await analyzeOriginalViaVertex(fileUri, 'image/jpeg');
    if ((!parsed || !parsed.length) && AGENT_ANALYSIS_URL) {
      parsed = await analyzeOriginalViaAgent(fileUri, 'image/jpeg');
    }
    if (Array.isArray(parsed)) {
      for (const it of parsed) {
        if (it?.name) {
          results.push({
            id: it.id ?? slugifyName(it.name),
            name: it.name,
            category: it.category ?? undefined,
            description: it.description ?? undefined,
            price: typeof it.price === 'number' ? it.price : undefined,
            currency: it.currency ?? undefined,
            sizes: Array.isArray(it.sizes) ? it.sizes.map((s: any) => String(s ?? '').trim()).filter(Boolean) : undefined,
            modifiers: Array.isArray(it.modifiers) ? it.modifiers.map((s: any) => String(s ?? '').trim()).filter(Boolean) : undefined,
            available: it.available ?? true,
            imageUrl: undefined,
            photoUrl: undefined,
          });
        }
      }
    }
    if (jobId && nodeId) {
      if (parsed && Array.isArray(parsed) && parsed.length) {
        await finishWorkflowNode(jobId, nodeId, { meta: { items: parsed.length } });
      } else {
        await failWorkflowNode(jobId, nodeId, 'no items found');
      }
    }
  }
  return results;
}

async function analyzeOriginalViaVertex(fileUri: string, mimeType: string): Promise<any[]> {
  const prompt =
    'Read this menu page image and return a strict JSON array of menu items. ' +
    'Use ONLY visible text. Do NOT invent items, modifiers, sizes, or combo contents. ' +
    'Return array items with shape:\n' +
    '[{\n' +
    '  "id": string (stable, slug-like; if missing, omit and we will derive),\n' +
    '  "name": string,\n' +
    '  "category": string (optional),\n' +
    '  "description": string (optional),\n' +
    '  "price": number (optional, in major units like 5.99),\n' +
    '  "currency": "USD"|"EUR"|"GBP" (optional; map symbols $,€,£),\n' +
    '  "available": boolean (optional; default true),\n' +
    '  "sizes": string[] (optional; e.g. ["Small","Large"] if sizes are explicitly listed),\n' +
    '  "modifiers": string[] (optional; flat list of explicitly listed options like toppings/sauces)\n' +
    '}]\n' +
    'If a field is not visible, omit it. Output JSON only.';
  const body = {
    contents: [
      {
        role: 'user',
        parts: [
          { text: prompt },
          { fileData: { fileUri, mimeType } },
        ],
      },
    ],
    generationConfig: {
      responseMimeType: 'application/json',
      temperature: 0.2,
    },
  };

  const url = `https://aiplatform.googleapis.com/v1/projects/${process.env.GOOGLE_CLOUD_PROJECT}/locations/global/publishers/google/models/${ANALYSIS_MODEL}:generateContent`;

  try {
    const token = await auth.getAccessToken();
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), Number(process.env.GEN_TIMEOUT_MS ?? 120_000));
    let res: any;
    let resText = '';
    try {
      res = await fetch(url, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      resText = await res.text();
    } finally {
      clearTimeout(timeout);
    }
    const contentType = res.headers.get('content-type') || '';
    if (!res.ok || !contentType.includes('application/json')) {
      console.error('analyze-original fetch failed', {
        status: res.status,
        statusText: res.statusText,
        bodySnippet: resText.slice(0, 400),
        contentType,
      });
      return [];
    }
    let parsedResp: any;
    try {
      parsedResp = JSON.parse(resText);
    } catch (e) {
      console.error('analyze-original response parse error', { message: (e as Error).message, resText: resText.slice(0, 200) });
      return [];
    }
    const text =
      parsedResp?.candidates
        ?.flatMap((c: any) => c?.content?.parts ?? [])
        ?.find((p: any) => p?.text)?.text;
    if (!text) return [];
    try {
      const parsed = JSON.parse(text);
      return Array.isArray(parsed) ? parsed : [];
    } catch (e) {
      console.error('analyze original parse error', e);
      return [];
    }
  } catch (err) {
    console.error('analyze-original error', err);
    const docId = `analysis-${slugifyName(fileUri)}-${Buffer.from(fileUri).toString('base64').slice(0, 8)}`;
    const queued = await enqueueAgentJob('analysis', prompt, fileUri, mimeType, ANALYSIS_MODEL, docId);
    if (queued) {
      const res = await waitForAgentJob(queued, 'analysis');
      const text = res?.outputText;
      if (text) {
        try {
          const parsed = JSON.parse(text);
          return Array.isArray(parsed) ? parsed : [];
        } catch {
          return [];
        }
      }
    }
    return [];
  }
}

async function analyzeOriginalViaAgent(fileUri: string, _mimeType: string): Promise<any[]> {
  if (!AGENT_ANALYSIS_URL) return [];
  try {
    const [signedUrl] = await storage.bucket(BUCKET).file(fileUri.replace(`gs://${BUCKET}/`, '')).getSignedUrl({
      action: 'read',
      expires: Date.now() + 15 * 60 * 1000,
    });
    const res = await fetchGradio(
      AGENT_ANALYSIS_URL,
      'Extract menu items as strict JSON array with fields [{id,name,category,description,price,currency,available,sizes,modifiers}]. Use only visible text; do not invent.',
      signedUrl
    );
    if (!res) return [];
    if (res.text) {
      try {
        const arr = JSON.parse(res.text);
        return Array.isArray(arr) ? arr : [];
      } catch {
        return [];
      }
    }
    return [];
  } catch (err) {
    console.error('analyzeOriginalViaAgent error', err);
    return [];
  }
}

export async function generateComposites(files: string[], jobId: string): Promise<GeneratedComposite> {
  const generatedFiles: string[] = [];
  let page = 0;
  for (const object of files.slice(0, MAX_PAGES)) {
    page += 1;
    try {
      const prompt =
        'So this is a page, a part of a menu of fast food containing different items, bundles, etc, probably organized by categories, with maybe a text next to each item with a price probably, or maybe a description. ' +
        'Can you separate all of these purchasable elements of the menu in a composite in order to use them as thumbnails into a menu visualizer for the personnel of the fast food and the clients? ' +
        'Keep each dish together with its text and price. Output one image with all separated dishes neatly laid out on white.';

      let b64: string | undefined;

      const compositeNodeId = `composite_p${page}`;
      await startWorkflowNode(jobId, {
        id: compositeNodeId,
        parentId: `analysis_p${page}`,
        kind: 'composite',
        label: `Composite page ${page}`,
        modelId: COMPOSITE_MODEL,
        fileUri: `gs://${BUCKET}/${object}`,
        page,
        seq: 2000 + page,
      });

      b64 = await renderImage({
        prompt,
        mimeType: 'image/jpeg',
        fileUri: `gs://${BUCKET}/${object}`,
        modelId: COMPOSITE_MODEL,
        label: `composite-${jobId}-p${page}`,
      });

      if (!b64 && AGENT_COMPOSITE_URL) {
        try {
          const agentNodeId = `${compositeNodeId}_agent`;
          await startWorkflowNode(jobId, {
            id: agentNodeId,
            parentId: compositeNodeId,
            kind: 'composite_agent',
            label: `Composite page ${page} (agent)`,
            fileUri: `gs://${BUCKET}/${object}`,
            page,
            seq: 2000 + page * 10 + 1,
          });
          const buf = await renderCompositeViaAgent(object, prompt);
          if (buf) {
            b64 = buf.toString('base64');
            await finishWorkflowNode(jobId, agentNodeId, { meta: { source: 'agent' } });
          } else {
            await failWorkflowNode(jobId, agentNodeId, 'agent returned empty image');
          }
        } catch (agentErr) {
          console.error('agent composite error', agentErr);
          await failWorkflowNode(jobId, `${compositeNodeId}_agent`, agentErr);
        }
      }

      if (!b64) {
        console.warn(`composite generation returned empty image for page ${page}, skipping extraction for this page`);
        await failWorkflowNode(jobId, compositeNodeId, 'composite generation returned empty image');
        continue; // do not fall back to original; composite is required for downstream extraction
      }
      const compositeBuffer = Buffer.from(b64, 'base64');
      const dest = `menu-generated/${jobId}/page-${page}.png`;
      await withTimeout(
        storage.bucket(BUCKET).file(dest).save(compositeBuffer, {
          contentType: 'image/png',
          resumable: false,
          metadata: { cacheControl: 'public,max-age=86400' },
        }),
        GCS_OP_TIMEOUT_MS,
        `gcs-save-composite-${jobId}-p${page}`,
      );
      generatedFiles.push(dest);
      const [url] = await withTimeout(
        storage
          .bucket(BUCKET)
          .file(dest)
          .getSignedUrl({ action: 'read', expires: Date.now() + 7 * 24 * 60 * 60 * 1000 }),
        GCS_OP_TIMEOUT_MS,
        `gcs-signedurl-composite-${jobId}-p${page}`,
      );
      await finishWorkflowNode(jobId, compositeNodeId, { meta: { dest, url } });
    } catch (err: any) {
      console.error('generate composite', err);
      // Do not add original to generatedFiles; composite is required for extraction.
      await failWorkflowNode(jobId, `composite_p${page}`, err);
    }
  }

  if (generatedFiles.length === 0) {
    throw new Error('no composites generated');
  }
  return { generatedFiles };
}

export async function extractItemsFromComposites(files: string[], jobId: string): Promise<ExtractedItems> {
  const results: GeminiItemImage[] = [];
  let detectedCount = 0;
  let page = 0;
  for (const object of files) {
    page += 1;
    try {
      const mime =
        object.toLowerCase().endsWith('.png') ? 'image/png' : object.toLowerCase().match(/\.jpe?g$/) ? 'image/jpeg' : 'image/png';
      const countPrompt =
        'How many individual cards/items are in this composite image? Return strict JSON like { "count": 12 } with no other text.';
      const countNodeId = `count_p${page}`;
      const compositeNodeId = `composite_p${page}`;
      await startWorkflowNode(jobId, {
        id: countNodeId,
        parentId: compositeNodeId,
        kind: 'count',
        label: `Count items (page ${page})`,
        modelId: ANALYSIS_MODEL,
        fileUri: `gs://${BUCKET}/${object}`,
        page,
        seq: 3000 + page,
      });
      const countResp = await geminiJson(countPrompt, `gs://${BUCKET}/${object}`, mime, ANALYSIS_MODEL, `count-${jobId}-p${page}`);
      let count = Number(countResp?.count ?? 0);
      if (!count || Number.isNaN(count)) {
        await failWorkflowNode(jobId, countNodeId, 'gemini item count missing', { meta: { raw: countResp } });
        throw new Error('gemini item count missing');
      }
      count = Math.min(count, MAX_ITEMS_PER_PAGE);
      detectedCount = Math.max(detectedCount, count);
      await finishWorkflowNode(jobId, countNodeId, { meta: { count } });

      let totalSoFar = results.length;
      for (let idx = 1; idx <= count && totalSoFar < MAX_TOTAL_ITEMS; idx++, totalSoFar++) {
        const renderNodeId = `render_p${page}_i${idx}`;
        const imgPrompt = `Give me element #${idx} from this composite (the ${ordinal(
          idx
        )} purchasable menu item). Render it alone on a clean white background with its text and price visible. Return only the image (png).`;
        await startWorkflowNode(jobId, {
          id: renderNodeId,
          parentId: compositeNodeId,
          kind: 'render_item',
          label: `Render item ${idx} (page ${page})`,
          modelId: RENDER_MODEL,
          fileUri: `gs://${BUCKET}/${object}`,
          page,
          itemIndex: idx,
          seq: 4000 + page * 100 + idx,
        });
        try {
          const imageB64 = await renderImage({
            prompt: imgPrompt,
            mimeType: mime,
            fileUri: `gs://${BUCKET}/${object}`,
            modelId: RENDER_MODEL,
            label: `render-${jobId}-p${page}-i${idx}`,
          });
          if (!imageB64) {
            throw new Error(`rendered item #${idx} missing`);
          }
          const imageBuffer = Buffer.from(imageB64, 'base64');
          const dest = `menu-items/${jobId}/page-${page}-item-${idx}.png`;
          await withTimeout(
            storage.bucket(BUCKET).file(dest).save(imageBuffer, {
              contentType: 'image/png',
              resumable: false,
              metadata: { cacheControl: 'public,max-age=86400' },
            }),
            GCS_OP_TIMEOUT_MS,
            `gcs-save-item-${jobId}-p${page}-i${idx}`,
          );
          const [url] = await withTimeout(
            storage
              .bucket(BUCKET)
              .file(dest)
              .getSignedUrl({ action: 'read', expires: Date.now() + 7 * 24 * 60 * 60 * 1000 }),
            GCS_OP_TIMEOUT_MS,
            `gcs-signedurl-item-${jobId}-p${page}-i${idx}`,
          );
          results.push({ name: `item_${page}_${idx}`, url, storagePath: dest });
          await finishWorkflowNode(jobId, renderNodeId, { meta: { dest, url } });
        } catch (err) {
          await failWorkflowNode(jobId, renderNodeId, err);
          // Continue extracting other items on this page (best-effort).
          continue;
        }
      }
    } catch (err) {
      console.error('extract items from composite error', err);
    }
  }
  return { images: results, count: detectedCount };
}

export async function assignThumbsToMenu(menu: MenuItem[], thumbs: GeminiItemImage[], jobId?: string): Promise<MenuItem[]> {
  const menuJson = menu.length ? JSON.stringify(menu) : undefined;
  const thumbItems: MenuItem[] = [];

  for (const thumb of thumbs) {
    const parsed = await describeThumbWithContext(menuJson, thumb, jobId);
    thumbItems.push(parsedToItem(parsed, thumb));
  }

  if (!menu.length) return thumbItems;
  return mergeMenuWithThumbs(menu, thumbItems);
}

async function describeThumbWithContext(menuJson: string | undefined, thumb: GeminiItemImage, jobId?: string): Promise<any> {
  const prompt =
    'You will be given a menu (as JSON) and a thumbnail image of a menu item. ' +
    'Return JSON for the best matching item with fields {id, name, category, price, currency, available}. ' +
    'Prefer ids/names from the provided menu if they match the thumbnail. ' +
    'If no menu is provided, infer from the image only. ' +
    (menuJson ? `Menu JSON: ${menuJson}` : 'No menu JSON provided.');

  try {
    const mime =
      thumb.storagePath.toLowerCase().endsWith('.png')
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

async function renderCompositeViaAgent(object: string, prompt: string): Promise<Buffer | undefined> {
  if (!AGENT_COMPOSITE_URL) return undefined;
  try {
    const [signedUrl] = await storage.bucket(BUCKET).file(object).getSignedUrl({
      action: 'read',
      expires: Date.now() + 15 * 60 * 1000,
    });

    const res = await fetchGradio(AGENT_COMPOSITE_URL, prompt, signedUrl);
    if (!res) return undefined;

    if (res.inlineData) return Buffer.from(res.inlineData, 'base64');
    if (res.url) {
      const fetchRes = await fetch(res.url);
      if (!fetchRes.ok) return undefined;
      const arrayBuf = await fetchRes.arrayBuffer();
      return Buffer.from(arrayBuf);
    }
    return undefined;
  } catch (err) {
    console.error('renderCompositeViaAgent error', err);
    return undefined;
  }
}

async function fetchGradio(baseUrl: string, text: string, fileUrl: string): Promise<GradioResult | undefined> {
  const form = new FormData();
  form.append('data', text);
  form.append('file', fileUrl);

  const paths = [`${baseUrl}/chat`, `${baseUrl}/chat/`];
  let last: Response | undefined;
  for (let attempt = 1; attempt <= AGENT_RETRIES; attempt++) {
    for (const url of paths) {
      const res = await fetch(url, { method: 'POST', body: form });
      last = res;
      if (res.status === 404) continue;
      if (res.status === 429 || res.status >= 500) {
        if (attempt < AGENT_RETRIES) {
          const backoff = AGENT_BASE_DELAY_MS * Math.pow(2, attempt - 1);
          const jitter = Math.floor(Math.random() * 500);
          await delay(backoff + jitter);
          break;
        }
      }
      try {
        const parsed: any = await res.json();
        const data = parsed?.data ?? parsed;
        if (Array.isArray(data) && data.length) {
          const first = data[0];
          if (typeof first === 'string') return { text: first };
          if (first?.url) return { url: first.url };
          if (first?.path) return { url: first.path };
          if (first?.data) return { inlineData: first.data };
        }
      } catch {
        // ignore
      }
      return undefined;
    }
  }
  return undefined;
}
