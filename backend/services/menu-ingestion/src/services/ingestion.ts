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
import { geminiImage, geminiJson, renderImage } from './generation.js';
import type { DraftMenu, MenuItem } from '../types.js';

const storage = new Storage();
const firestore = new Firestore({ ignoreUndefinedProperties: true });
const BUCKET = (BUCKET_ENV || "") as string;
const auth = new GoogleAuth({ scopes: 'https://www.googleapis.com/auth/cloud-platform' });

// Cost safeguards
const MAX_PAGES = Number(process.env.MENU_MAX_PAGES ?? 5);
const MAX_ITEMS_PER_PAGE = Number(process.env.MENU_MAX_ITEMS_PER_PAGE ?? 40);
const MAX_TOTAL_ITEMS = Number(process.env.MENU_MAX_TOTAL_ITEMS ?? 120);

export type GeneratedComposite = { generatedFiles: string[] };
export type ExtractedItems = { images: GeminiItemImage[]; count: number };
export type GeminiItemImage = { name: string; url: string; storagePath: string };
type GradioResult = { text?: string; inlineData?: string; url?: string };

export async function analyzeMenuFromOriginal(files: string[]): Promise<MenuItem[]> {
  const results: MenuItem[] = [];
  for (const object of files) {
    const fileUri = `gs://${BUCKET}/${object}`;
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
            price: typeof it.price === 'number' ? it.price : undefined,
            currency: it.currency ?? undefined,
            available: it.available ?? true,
            imageUrl: undefined,
            photoUrl: undefined,
          });
        }
      }
    }
  }
  return results;
}

async function analyzeOriginalViaVertex(fileUri: string, mimeType: string): Promise<any[]> {
  const prompt =
    'Read this menu page image and return JSON array of items: [{id, name, category, price, currency, available}]. ' +
    'Use only visible text; map €, £, $ to EUR, GBP, USD. Do not invent items.';
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
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    clearTimeout(timeout);
    const contentType = res.headers.get('content-type') || '';
    const resText = await res.text();
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
    const res = await fetchGradio(AGENT_ANALYSIS_URL, 'Extract menu items as JSON array [{id,name,category,price,currency,available}]', signedUrl);
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

      b64 = await renderImage({
        prompt,
        mimeType: 'image/jpeg',
        fileUri: `gs://${BUCKET}/${object}`,
        modelId: COMPOSITE_MODEL,
        label: `composite-${jobId}-p${page}`,
      });

      if (!b64 && AGENT_COMPOSITE_URL) {
        try {
          const buf = await renderCompositeViaAgent(object, prompt);
          if (buf) {
            b64 = buf.toString('base64');
          }
        } catch (agentErr) {
          console.error('agent composite error', agentErr);
        }
      }

      if (!b64) {
        throw new Error(`composite generation returned empty image for page ${page}`);
      }
      const compositeBuffer = Buffer.from(b64, 'base64');
      const dest = `menu-generated/${jobId}/page-${page}.png`;
      await storage.bucket(BUCKET).file(dest).save(compositeBuffer, {
        contentType: 'image/png',
        resumable: false,
        metadata: { cacheControl: 'public,max-age=86400' },
      });
      generatedFiles.push(dest);
    } catch (err: any) {
      console.error('generate composite', err);
      throw err;
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
      const countPrompt =
        'How many individual cards/items are in this composite image? Return strict JSON like { "count": 12 } with no other text.';
      const countResp = await geminiJson(countPrompt, `gs://${BUCKET}/${object}`, 'image/png', ANALYSIS_MODEL);
      let count = Number(countResp?.count ?? 0);
      if (!count || Number.isNaN(count)) {
        throw new Error('gemini item count missing');
      }
      count = Math.min(count, MAX_ITEMS_PER_PAGE);
      detectedCount = Math.max(detectedCount, count);

      let totalSoFar = results.length;
      for (let idx = 1; idx <= count && totalSoFar < MAX_TOTAL_ITEMS; idx++, totalSoFar++) {
        const imgPrompt = `Give me element #${idx} from this composite (the ${ordinal(
          idx
        )} purchasable menu item). Render it alone on a clean white background with its text and price visible. Return only the image (png).`;
        const imageB64 = await renderImage({
          prompt: imgPrompt,
          mimeType: 'image/png',
          fileUri: `gs://${BUCKET}/${object}`,
          modelId: RENDER_MODEL,
          label: `render-${jobId}-p${page}-i${idx}`,
        });
        if (!imageB64) {
          throw new Error(`rendered item #${idx} missing`);
        }
        const imageBuffer = Buffer.from(imageB64, 'base64');
        const dest = `menu-items/${jobId}/page-${page}-item-${idx}.png`;
        await storage.bucket(BUCKET).file(dest).save(imageBuffer, {
          contentType: 'image/png',
          resumable: false,
          metadata: { cacheControl: 'public,max-age=86400' },
        });
        const [url] = await storage
          .bucket(BUCKET)
          .file(dest)
          .getSignedUrl({ action: 'read', expires: Date.now() + 7 * 24 * 60 * 60 * 1000 });
        results.push({ name: `item_${page}_${idx}`, url, storagePath: dest });
      }
    } catch (err) {
      console.error('extract items from composite error', err);
    }
  }
  return { images: results, count: detectedCount };
}

export async function assignThumbsToMenu(menu: MenuItem[], thumbs: GeminiItemImage[]): Promise<MenuItem[]> {
  const menuJson = menu.length ? JSON.stringify(menu) : undefined;
  const thumbItems: MenuItem[] = [];

  for (const thumb of thumbs) {
    const parsed = await describeThumbWithContext(menuJson, thumb);
    thumbItems.push(parsedToItem(parsed, thumb));
  }

  if (!menu.length) return thumbItems;
  return mergeMenuWithThumbs(menu, thumbItems);
}

async function describeThumbWithContext(menuJson: string | undefined, thumb: GeminiItemImage): Promise<any> {
  const prompt =
    'You will be given a menu (as JSON) and a thumbnail image of a menu item. ' +
    'Return JSON for the best matching item with fields {id, name, category, price, currency, available}. ' +
    'Prefer ids/names from the provided menu if they match the thumbnail. ' +
    'If no menu is provided, infer from the image only. ' +
    (menuJson ? `Menu JSON: ${menuJson}` : 'No menu JSON provided.');

  try {
    const resp = await geminiJson(prompt, `gs://${BUCKET}/${thumb.storagePath}`, 'image/png', ANALYSIS_MODEL);
    return resp ?? {};
  } catch (err) {
    console.error('describe-thumb error', err);
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
