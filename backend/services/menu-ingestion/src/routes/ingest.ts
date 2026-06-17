import express from 'express';
import { v4 as uuidv4 } from 'uuid';
import type { AppContext } from '../app.js';
import type { IngestJob, IngestStartRequest, DraftMenu } from '../types.js';
import { IngestionLimitError, parseRequestedPageCount } from '../ingestion_limits.js';
import { analyzeMenuFromOriginal, assignThumbsToMenu, extractItemsFromComposites, generateComposites } from '../services/ingestion.js';
import { mapDraftItemsToOrderServiceMenu } from '../services/order-service-sync.js';

export function ingestRouter(ctx: AppContext) {
  const router = express.Router();
  const { firestore, storage, pubsub, bucket, topic, menuUpdatesTopic, signedReadUrls, requireAuth } = ctx;

  // List recent jobs
  router.get('/ingest', requireAuth, async (req, res) => {
    const limit = Number(req.query.limit ?? 20);
    const showCounts = req.query.counts === 'true';
    const snap = await firestore
      .collection('menus_ingest')
      .orderBy('updatedAt', 'desc')
      .limit(Math.max(1, Math.min(limit, 50)))
      .get();
    const jobs = snap.docs.map((d) => d.data());
    if (!showCounts) {
      return res.json({ jobs });
    }
    const backlog = await firestore
      .collection('menus_ingest')
      .where('status', 'in', ['queued', 'processing'])
      .count()
      .get();
    const dlq = await firestore
      .collection('menus_ingest')
      .where('status', '==', 'error')
      .count()
      .get();
    res.json({ jobs, backlog: backlog.data().count, dlq: dlq.data().count });
  });

  // 1) Start: generate signed URLs for uploads
  router.post('/ingest/start', requireAuth, async (req, res) => {
    const body = req.body as IngestStartRequest;
    const restaurantId = String(body.restaurantId ?? '').trim();
    if (!restaurantId) {
      return res.status(400).json({ error: 'restaurantId and pageCount are required' });
    }
    let pageCount: number;
    try {
      pageCount = parseRequestedPageCount(body.pageCount);
    } catch (err) {
      if (err instanceof IngestionLimitError) {
        return res.status(400).json({ error: err.code, message: err.message, ...err.details });
      }
      throw err;
    }

    const jobId = uuidv4();
    const now = Date.now();
    const files: string[] = [];
    const signedUrls: string[] = [];

    for (let i = 0; i < pageCount; i++) {
      const object = `menu-raw/${restaurantId}/${jobId}/page-${i + 1}.jpg`;
      const [url] = await storage.bucket(bucket).file(object).getSignedUrl({
        action: 'write',
        expires: Date.now() + 15 * 60 * 1000,
        contentType: 'image/jpeg',
      });
      files.push(object);
      signedUrls.push(url);
    }

    const job: IngestJob = {
      jobId,
      restaurantId,
      status: 'uploading',
      files,
      createdAt: now,
      updatedAt: now,
    };

    await firestore.collection('menus_ingest').doc(jobId).set(job);

    res.json({ jobId, uploadUrls: signedUrls });
  });

  // 2) Submit for processing (after uploads)
  router.post('/ingest/submit', requireAuth, async (req, res) => {
    const { jobId } = req.body as { jobId?: string };
    if (!jobId) return res.status(400).json({ error: 'jobId required' });

    const jobRef = firestore.collection('menus_ingest').doc(jobId);
    const snap = await jobRef.get();
    if (!snap.exists) return res.status(404).json({ error: 'job not found' });
    const job = snap.data() as IngestJob;
    const status = String(job.status ?? '').trim();
    if (status === 'ready') {
      return res.status(409).json({ error: 'job_already_ready' });
    }
    if (status === 'canceled' || job.cancelRequestedAt) {
      return res.status(409).json({ error: 'job_canceled' });
    }
    if (status === 'queued' || status === 'processing') {
      return res.json({ jobId, status });
    }

    await jobRef.update({
      status: 'queued',
      progressStage: 'queued',
      progressPercent: 0,
      updatedAt: Date.now(),
    });
    await pubsub.topic(topic).publishMessage({ json: { jobId } });

    res.json({ jobId, status: 'queued' });
  });

  // 3) Poll job
  router.get('/ingest/:jobId', requireAuth, async (req, res) => {
    const snap = await firestore.collection('menus_ingest').doc(req.params.jobId).get();
    if (!snap.exists) return res.status(404).json({ error: 'not found' });
    res.json(snap.data());
  });

  // 3b) Fetch draft (including items and viewable image URLs)
  router.get('/ingest/:jobId/draft', requireAuth, async (req, res) => {
    const { jobId } = req.params;
    const draftSnap = await firestore.collection('menus_drafts').doc(jobId).get();
    if (!draftSnap.exists) return res.status(404).json({ error: 'draft not found' });

    const jobSnap = await firestore.collection('menus_ingest').doc(jobId).get();
    const files = jobSnap.exists ? (jobSnap.data() as IngestJob).files : [];
    const fileUrls = files.length ? await signedReadUrls(files) : [];

    res.json({
      jobId,
      draft: draftSnap.data(),
      files,
      fileUrls,
    });
  });

  // 4) Approve draft
  router.post('/ingest/:jobId/approve', requireAuth, async (req, res) => {
    const { jobId } = req.params;
    const draftSnap = await firestore.collection('menus_drafts').doc(jobId).get();
    if (!draftSnap.exists) return res.status(404).json({ error: 'draft not found' });
    const draft = draftSnap.data() as DraftMenu;

    const batch = firestore.batch();
    const menuColl = firestore
      .collection('restaurants')
      .doc(draft.restaurantId)
      .collection('menus');

    draft.items.forEach((item) => {
      const id = item.id || uuidv4();
      batch.set(menuColl.doc(id), item, { merge: true });
    });

    batch.update(firestore.collection('menus_ingest').doc(jobId), {
      status: 'ready',
      updatedAt: Date.now(),
    });

    // Upsert the canonical menu used by order-service (/stores/{storeID}/menu/snapshot)
    const orderServiceMenu = mapDraftItemsToOrderServiceMenu(draft);
    batch.set(firestore.collection('menus').doc(draft.restaurantId), orderServiceMenu, {
      merge: true,
    });

    await batch.commit();

    if (menuUpdatesTopic) {
      try {
        await pubsub.topic(menuUpdatesTopic).publishMessage({
          json: {
            storeId: draft.restaurantId,
            updatedAt: orderServiceMenu.updatedAt,
            jobId,
            source: 'menu-ingestion',
          },
        });
      } catch (err) {
        console.warn('menu-updates publish failed', err);
      }
    }

    res.json({ status: 'published', items: draft.items.length });
  });

  // 5) Cancel job (best-effort)
  router.post('/ingest/:jobId/cancel', requireAuth, async (req, res) => {
    const { jobId } = req.params;
    const jobRef = firestore.collection('menus_ingest').doc(jobId);
    const snap = await jobRef.get();
    if (!snap.exists) return res.status(404).json({ error: 'job not found' });
    const now = Date.now();
    await jobRef.update({
      status: 'canceled',
      cancelRequestedAt: now,
      progressStage: 'canceled',
      progressPercent: 100,
      updatedAt: now,
    });
    res.json({ jobId, status: 'canceled' });
  });

  return router;
}
