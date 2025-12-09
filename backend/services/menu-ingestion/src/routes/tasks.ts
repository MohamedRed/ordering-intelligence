import express from 'express';
import type { AppContext } from '../app.js';
import type { IngestJob, DraftMenu } from '../types.js';
import {
  analyzeMenuFromOriginal,
  generateComposites,
  extractItemsFromComposites,
  assignThumbsToMenu,
} from '../services/ingestion.js';

function parsePubSubBody(body: any): any {
  if (body?.message?.data) {
    const raw = Buffer.from(body.message.data, 'base64').toString('utf8');
    try {
      return JSON.parse(raw);
    } catch {
      return undefined;
    }
  }
  return body;
}

export function tasksRouter(ctx: AppContext) {
  const router = express.Router();
  const { firestore, storage, bucket, signedReadUrls } = ctx;

  async function processJob(jobId: string, job: IngestJob) {
    try {
      const menuFromOriginal = await analyzeMenuFromOriginal(job.files);

      const composites = await generateComposites(job.files, jobId);
      const compositeUrls = await signedReadUrls(composites.generatedFiles);
      const extracted = await extractItemsFromComposites(composites.generatedFiles, jobId);
      let geminiItems = extracted.images;

      if (!geminiItems.length && composites.generatedFiles.length) {
        const first = composites.generatedFiles[0];
        const [url] = await storage
          .bucket(bucket)
          .file(first)
          .getSignedUrl({ action: 'read', expires: Date.now() + 7 * 24 * 60 * 60 * 1000 });
        geminiItems = [{ name: 'menu_page_1', url, storagePath: first }];
      }

      const items = await assignThumbsToMenu(menuFromOriginal, geminiItems);

      if (!items.length) {
        throw new Error('no items extracted from thumbnails');
      }

      const draft: DraftMenu = {
        jobId,
        restaurantId: job.restaurantId,
        items,
        ocrLines: [],
        compositeUrls,
        detectedItemCount: menuFromOriginal.length || extracted.count,
        createdAt: job.createdAt,
        updatedAt: Date.now(),
      };

      await firestore.collection('menus_drafts').doc(jobId).set(draft);
      await firestore
        .collection('menus_ingest')
        .doc(jobId)
        .update({
          status: 'ready',
          draftRef: `menus_drafts/${jobId}`,
          processedAt: Date.now(),
          updatedAt: Date.now(),
        });
    } catch (error: any) {
      console.error('ingest failed', { jobId, error });
      await firestore
        .collection('menus_ingest')
        .doc(jobId)
        .update({ status: 'error', issues: [String(error?.message ?? error)], updatedAt: Date.now() });
    }
  }

  router.post('/tasks/process', async (req, res) => {
    const message = parsePubSubBody(req.body);
    if (!message?.jobId) {
      return res.status(400).json({ error: 'missing jobId' });
    }

    const jobId = message.jobId as string;
    const jobRef = firestore.collection('menus_ingest').doc(jobId);

    // Guard against duplicate/looped deliveries: only transition queued/uploading -> processing.
    const now = Date.now();
    const jobSnap = await firestore.runTransaction(async (tx) => {
      const snap = await tx.get(jobRef);
      if (!snap.exists) return null;
      const data = snap.data() as IngestJob;
      // Allow re-drive if a processing job expired its window.
      const processingExpired =
        data.status === 'processing' && data.processingExpiresAt && now > data.processingExpiresAt;
      if (data.processedAt || ['ready'].includes(data.status)) {
        return { skip: true, data };
      }
      if (!processingExpired && data.status === 'processing') {
        return { skip: true, data };
      }
      const expiresAt = Date.now() + 30 * 60 * 1000; // 30m safety window
      tx.update(jobRef, { status: 'processing', updatedAt: Date.now() });
      tx.update(jobRef, { processingExpiresAt: expiresAt });
      return { skip: false, data: { ...data, processingExpiresAt: expiresAt } };
    });

    if (!jobSnap) {
      return res.status(404).json({ error: 'job not found' });
    }
    if (jobSnap.skip) {
      return res.json({ ok: true, skipped: true });
    }

    // Kick off processing asynchronously to return 200 quickly (prevents Pub/Sub redelivery loops).
    void processJob(jobId, jobSnap.data as IngestJob);

    res.json({ ok: true, queued: true });
  });

  return router;
}
