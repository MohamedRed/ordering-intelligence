import express from 'express';
import type { AppContext } from '../app.js';
import type { IngestJob, DraftMenu } from '../types.js';
import { assertFilesWithinPageLimit } from '../ingestion_limits.js';
import {
  analyzeMenuFromOriginal,
  generateComposites,
  extractItemsFromComposites,
  assignThumbsToMenu,
} from '../services/ingestion.js';
import { normalizeMenuStructure } from '../services/normalize_menu.js';
import { ensureWorkflowRoot, finishWorkflowNode } from '../services/workflow.js';

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
  const { firestore, storage, bucket, signedReadUrls, requireAuth } = ctx;
  const disableAsyncProcessing =
    String(process.env.DISABLE_TASK_PROCESSING || '').toLowerCase() === 'true' ||
    String(process.env.NODE_ENV || '').toLowerCase() === 'test';

  class CanceledError extends Error {
    constructor() {
      super('canceled');
      this.name = 'CanceledError';
    }
  }

  async function processJob(jobId: string, job: IngestJob) {
    const jobRef = firestore.collection('menus_ingest').doc(jobId);
    const setProgress = async (progressStage: string, progressPercent: number) => {
      try {
        await jobRef.update({
          progressStage,
          progressPercent,
          updatedAt: Date.now(),
        });
      } catch {
        // Best-effort progress updates; ignore failures.
      }
    };
    const ensureNotCanceled = async () => {
      const snap = await jobRef.get();
      const data = snap.exists ? (snap.data() as IngestJob) : undefined;
      if (data?.status === 'canceled' || data?.cancelRequestedAt) {
        throw new CanceledError();
      }
    };
    try {
      await ensureWorkflowRoot(jobId, job.restaurantId);
      await ensureNotCanceled();
      assertFilesWithinPageLimit(job.files);
      const pipelineMode = (job.pipelineMode ?? 'full') as 'menu_only' | 'full';
      const nowMs = Date.now();

      // If a previous draft exists, use it as the canonical menu for "full" mode.
      let existingDraft: DraftMenu | null = null;
      try {
        const snap = await firestore.collection('menus_drafts').doc(jobId).get();
        if (snap.exists) {
          existingDraft = snap.data() as DraftMenu;
        }
      } catch {
        existingDraft = null;
      }

      // Step 2 (Fast): Analyze + normalize + write (no image enrichment).
      if (pipelineMode === 'menu_only') {
        await setProgress('analyze', 10);
        const menuFromOriginal = await analyzeMenuFromOriginal(job.files, jobId);
        await ensureNotCanceled();
        await setProgress('write', 80);
        const normalized = await normalizeMenuStructure({
          restaurantId: job.restaurantId,
          items: menuFromOriginal,
        });

        const draft: DraftMenu = {
          jobId,
          restaurantId: job.restaurantId,
          items: normalized.items,
          bundleRules: normalized.bundleRules,
          ocrLines: [],
          issues: normalized.issues.length ? normalized.issues : undefined,
          compositeUrls: [],
          detectedItemCount: menuFromOriginal.length,
          createdAt: job.createdAt,
          updatedAt: Date.now(),
        };

        await firestore.collection('menus_drafts').doc(jobId).set(draft, { merge: true });
        await firestore.collection('menus_ingest').doc(jobId).update({
          status: 'ready',
          readyKind: 'menu_only',
          draftRef: `menus_drafts/${jobId}`,
          processedAt: nowMs,
          progressStage: 'done',
          progressPercent: 100,
          updatedAt: Date.now(),
        });

        await finishWorkflowNode(jobId, 'root', { status: 'succeeded', meta: { items: normalized.items.length, readyKind: 'menu_only' } });
        return;
      }

      // Step 3 (Slow): Full pipeline. Prefer reusing a canonical draft from Step 2 if present.
      const baseMenu = existingDraft?.items?.length ? existingDraft.items : undefined;

      await setProgress('analyze', 10);
      const menuFromOriginal = baseMenu ?? (await analyzeMenuFromOriginal(job.files, jobId));

      await ensureNotCanceled();
      await setProgress('composites', 30);
      const composites = await generateComposites(job.files, jobId);
      const compositeUrls = await signedReadUrls(composites.generatedFiles);

      await ensureNotCanceled();
      await setProgress('extract', 60);
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

      await ensureNotCanceled();
      await setProgress('assign', 80);
      const enrichedItems = await assignThumbsToMenu(menuFromOriginal, geminiItems, jobId);

      if (!enrichedItems.length) {
        throw new Error('no items extracted from thumbnails');
      }

      await ensureNotCanceled();
      await setProgress('write', 90);

      // Always run normalization so modifierGroups/bundleRules exist even when no prior draft exists.
      const normalized = await normalizeMenuStructure({
        restaurantId: job.restaurantId,
        items: enrichedItems,
      });

      const mergedIssues = [
        ...(existingDraft?.issues ?? []),
        ...(normalized.issues ?? []),
      ].filter(Boolean);

      const draft: DraftMenu = {
        jobId,
        restaurantId: job.restaurantId,
        items: normalized.items,
        bundleRules: normalized.bundleRules,
        ocrLines: existingDraft?.ocrLines ?? [],
        issues: mergedIssues.length ? mergedIssues : undefined,
        compositeUrls,
        detectedItemCount: menuFromOriginal.length || extracted.count,
        createdAt: job.createdAt,
        updatedAt: Date.now(),
      };

      await firestore.collection('menus_drafts').doc(jobId).set(draft, { merge: true });
      await firestore.collection('menus_ingest').doc(jobId).update({
        status: 'ready',
        readyKind: 'full',
        draftRef: `menus_drafts/${jobId}`,
        processedAt: nowMs,
        progressStage: 'done',
        progressPercent: 100,
        updatedAt: Date.now(),
      });
      await finishWorkflowNode(jobId, 'root', { status: 'succeeded', meta: { items: draft.items.length, readyKind: 'full' } });
      if (process.env.VERBOSE_LOGGING === 'true') {
        console.log('ingest complete', {
          jobId,
          compositeCount: compositeUrls.length,
          items: draft.items.length,
          detected: draft.detectedItemCount,
        });
      }
    } catch (error: any) {
      if (error instanceof CanceledError || String(error?.message ?? '').toLowerCase() === 'canceled') {
        await firestore.collection('menus_ingest').doc(jobId).update({
          status: 'canceled',
          cancelRequestedAt: Date.now(),
          progressStage: 'canceled',
          progressPercent: 100,
          updatedAt: Date.now(),
        });
        await finishWorkflowNode(jobId, 'root', { status: 'canceled' });
        return;
      }
      console.error('ingest failed', { jobId, error });
      await firestore
        .collection('menus_ingest')
        .doc(jobId)
        .update({
          status: 'error',
          issues: [String(error?.message ?? error)],
          progressStage: 'error',
          progressPercent: 100,
          updatedAt: Date.now(),
        });
      await finishWorkflowNode(jobId, 'root', { status: 'error', error: String(error?.message ?? error) });
    }
  }

  router.post('/tasks/process', requireAuth, async (req, res) => {
    if (process.env.VERBOSE_LOGGING === 'true') {
      console.log('ingest task received', {
        messageId: req.body?.message?.messageId,
        jobId: req.body?.message?.attributes?.jobId ?? req.body?.jobId,
      });
    }
    const message = parsePubSubBody(req.body);
    if (!message?.jobId) {
      // Bad payloads should be acknowledged (200) to avoid Pub/Sub redelivery loops.
      console.warn('ingest task missing jobId', {
        messageId: req.body?.message?.messageId,
        attributes: req.body?.message?.attributes,
        keys: message ? Object.keys(message) : null,
      });
      return res.json({ ok: true, skipped: true, reason: 'missing jobId' });
    }

    const jobId = message.jobId as string;
    const jobRef = firestore.collection('menus_ingest').doc(jobId);

    // Guard against duplicate/looped deliveries: only transition queued/uploading -> processing.
    const now = Date.now();
    const jobSnap = await firestore.runTransaction(async (tx) => {
      const snap = await tx.get(jobRef);
      if (!snap.exists) return null;
      const data = snap.data() as IngestJob;
      const resumeRequestedAt = typeof data.resumeRequestedAt === 'number' ? data.resumeRequestedAt : 0;
      const processedAt = typeof data.processedAt === 'number' ? data.processedAt : 0;
      const wantsResume = resumeRequestedAt > 0 && (processedAt === 0 || resumeRequestedAt > processedAt);
      // Allow re-drive if a processing job expired its window.
      const processingExpired =
        data.status === 'processing' && data.processingExpiresAt && now > data.processingExpiresAt;
      if (!wantsResume && (data.processedAt || ['ready'].includes(data.status))) {
        return { skip: true, data };
      }
      if (data.status === 'canceled' || data.cancelRequestedAt) {
        return { skip: true, data };
      }
      if (!processingExpired && data.status === 'processing') {
        return { skip: true, data };
      }
      const expiresAt = Date.now() + 30 * 60 * 1000; // 30m safety window
      tx.update(jobRef, {
        status: 'processing',
        updatedAt: Date.now(),
        processingStartedAt: data.processingStartedAt ?? Date.now(),
        progressStage: wantsResume ? 'queued' : (data.progressStage ?? 'processing'),
        progressPercent: wantsResume ? 5 : (typeof data.progressPercent === 'number' ? data.progressPercent : 5),
        ...(wantsResume ? { issues: [] } : {}),
      });
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
    if (!disableAsyncProcessing) {
      void processJob(jobId, jobSnap.data as IngestJob);
    }

    res.json({ ok: true, queued: true, processingDisabled: disableAsyncProcessing ? true : undefined });
  });

  return router;
}
