import { Storage } from '@google-cloud/storage';
import {
  bucketEnv as BUCKET_ENV,
  AGENT_COMPOSITE_URL,
  ANALYSIS_MODEL,
  COMPOSITE_MODEL,
  RENDER_MODEL,
} from '../config.js';
import { assertFilesWithinPageLimit, ingestionLimits } from '../ingestion_limits.js';
import { ordinal } from '../utils.js';
import { geminiJson, renderImage } from './generation.js';
import { fetchGradio } from './gradio_client.js';
import type { ExtractedItems, GeneratedComposite, GeminiItemImage } from './ingestion_types.js';
import { resolveMenuObjectMimeType } from './menu_object_mime.js';
import { withTimeout } from './storage_timeout.js';
import {
  failWorkflowNode,
  finishWorkflowNode,
  startWorkflowNode,
} from './workflow.js';

const storage = new Storage();
const BUCKET = (BUCKET_ENV || '') as string;
const MAX_ITEMS_PER_PAGE = ingestionLimits.maxItemsPerPage;
const MAX_TOTAL_ITEMS = ingestionLimits.maxTotalItems;
const GCS_OP_TIMEOUT_MS = Number(process.env.GCS_OP_TIMEOUT_MS ?? 30_000);

export async function generateComposites(
  files: string[],
  jobId: string,
): Promise<GeneratedComposite> {
  assertFilesWithinPageLimit(files);
  const generatedFiles: string[] = [];
  let page = 0;
  for (const object of files) {
    page += 1;
    try {
      const prompt =
        'So this is a page, a part of a menu of fast food containing different items, bundles, etc, probably organized by categories, with maybe a text next to each item with a price probably, or maybe a description. ' +
        'Can you separate all of these purchasable elements of the menu in a composite in order to use them as thumbnails into a menu visualizer for the personnel of the fast food and the clients? ' +
        'Keep each dish together with its text and price. Output one image with all separated dishes neatly laid out on white.';

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

      const mimeType = resolveMenuObjectMimeType(object);
      let b64 = await renderImage({
        prompt,
        mimeType,
        fileUri: `gs://${BUCKET}/${object}`,
        modelId: COMPOSITE_MODEL,
        label: `composite-${jobId}-p${page}`,
      });

      if (!b64 && AGENT_COMPOSITE_URL) {
        b64 = await renderCompositeWithAgent(object, prompt, jobId, page, compositeNodeId);
      }

      if (!b64) {
        console.warn(`composite generation returned empty image for page ${page}, skipping extraction for this page`);
        await failWorkflowNode(jobId, compositeNodeId, 'composite generation returned empty image');
        continue;
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
      await failWorkflowNode(jobId, `composite_p${page}`, err);
    }
  }

  if (generatedFiles.length === 0) {
    throw new Error('no composites generated');
  }
  return { generatedFiles };
}

export async function extractItemsFromComposites(
  files: string[],
  jobId: string,
): Promise<ExtractedItems> {
  const results: GeminiItemImage[] = [];
  let detectedCount = 0;
  let page = 0;
  for (const object of files) {
    page += 1;
    try {
      const mime = resolveMenuObjectMimeType(object);
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
      const countResp = await geminiJson(
        countPrompt,
        `gs://${BUCKET}/${object}`,
        mime,
        ANALYSIS_MODEL,
        `count-${jobId}-p${page}`,
      );
      let count = Number(countResp?.count ?? 0);
      if (!count || Number.isNaN(count)) {
        await failWorkflowNode(jobId, countNodeId, 'gemini item count missing', { meta: { raw: countResp } });
        throw new Error('gemini item count missing');
      }
      count = Math.min(count, MAX_ITEMS_PER_PAGE);
      detectedCount = Math.max(detectedCount, count);
      await finishWorkflowNode(jobId, countNodeId, { meta: { count } });
      await renderCompositeItems({ object, mime, page, count, jobId, results, compositeNodeId });
    } catch (err) {
      console.error('extract items from composite error', err);
    }
  }
  return { images: results, count: detectedCount };
}

async function renderCompositeItems(params: {
  object: string;
  mime: string;
  page: number;
  count: number;
  jobId: string;
  results: GeminiItemImage[];
  compositeNodeId: string;
}): Promise<void> {
  let totalSoFar = params.results.length;
  for (let idx = 1; idx <= params.count && totalSoFar < MAX_TOTAL_ITEMS; idx++, totalSoFar++) {
    const renderNodeId = `render_p${params.page}_i${idx}`;
    const imgPrompt = `Give me element #${idx} from this composite (the ${ordinal(
      idx,
    )} purchasable menu item). Render it alone on a clean white background with its text and price visible. Return only the image (png).`;
    await startWorkflowNode(params.jobId, {
      id: renderNodeId,
      parentId: params.compositeNodeId,
      kind: 'render_item',
      label: `Render item ${idx} (page ${params.page})`,
      modelId: RENDER_MODEL,
      fileUri: `gs://${BUCKET}/${params.object}`,
      page: params.page,
      itemIndex: idx,
      seq: 4000 + params.page * 100 + idx,
    });
    try {
      const imageB64 = await renderImage({
        prompt: imgPrompt,
        mimeType: params.mime,
        fileUri: `gs://${BUCKET}/${params.object}`,
        modelId: RENDER_MODEL,
        label: `render-${params.jobId}-p${params.page}-i${idx}`,
      });
      if (!imageB64) {
        throw new Error(`rendered item #${idx} missing`);
      }
      const imageBuffer = Buffer.from(imageB64, 'base64');
      const dest = `menu-items/${params.jobId}/page-${params.page}-item-${idx}.png`;
      await withTimeout(
        storage.bucket(BUCKET).file(dest).save(imageBuffer, {
          contentType: 'image/png',
          resumable: false,
          metadata: { cacheControl: 'public,max-age=86400' },
        }),
        GCS_OP_TIMEOUT_MS,
        `gcs-save-item-${params.jobId}-p${params.page}-i${idx}`,
      );
      const [url] = await withTimeout(
        storage
          .bucket(BUCKET)
          .file(dest)
          .getSignedUrl({ action: 'read', expires: Date.now() + 7 * 24 * 60 * 60 * 1000 }),
        GCS_OP_TIMEOUT_MS,
        `gcs-signedurl-item-${params.jobId}-p${params.page}-i${idx}`,
      );
      params.results.push({ name: `item_${params.page}_${idx}`, url, storagePath: dest });
      await finishWorkflowNode(params.jobId, renderNodeId, { meta: { dest, url } });
    } catch (err) {
      await failWorkflowNode(params.jobId, renderNodeId, err);
    }
  }
}

async function renderCompositeWithAgent(
  object: string,
  prompt: string,
  jobId: string,
  page: number,
  compositeNodeId: string,
): Promise<string | undefined> {
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
    if (!buf) {
      await failWorkflowNode(jobId, agentNodeId, 'agent returned empty image');
      return undefined;
    }
    await finishWorkflowNode(jobId, agentNodeId, { meta: { source: 'agent' } });
    return buf.toString('base64');
  } catch (agentErr) {
    console.error('agent composite error', agentErr);
    await failWorkflowNode(jobId, `${compositeNodeId}_agent`, agentErr);
    return undefined;
  }
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
