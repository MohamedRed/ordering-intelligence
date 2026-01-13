import express from 'express';
import { v4 as uuidv4 } from 'uuid';
import type { AppContext } from '../app.js';
import type { IngestJob, IngestStartRequest, DraftMenu } from '../types.js';
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
  router.post('/ingest/start', async (req, res) => {
    const body = req.body as IngestStartRequest;
    if (!body.restaurantId || !body.pageCount || body.pageCount < 1) {
      return res.status(400).json({ error: 'restaurantId and pageCount are required' });
    }

    const jobId = uuidv4();
    const now = Date.now();
    const files: string[] = [];
    const signedUrls: string[] = [];

    for (let i = 0; i < body.pageCount; i++) {
      const object = `menu-raw/${body.restaurantId}/${jobId}/page-${i + 1}.jpg`;
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
      restaurantId: body.restaurantId,
      status: 'uploading',
      files,
      createdAt: now,
      updatedAt: now,
    };

    await firestore.collection('menus_ingest').doc(jobId).set(job);

    res.json({ jobId, uploadUrls: signedUrls });
  });

  // 2) Submit for processing (after uploads)
  router.post('/ingest/submit', async (req, res) => {
    const { jobId } = req.body as { jobId?: string };
    if (!jobId) return res.status(400).json({ error: 'jobId required' });

    const jobRef = firestore.collection('menus_ingest').doc(jobId);
    const snap = await jobRef.get();
    if (!snap.exists) return res.status(404).json({ error: 'job not found' });

    await jobRef.update({ status: 'queued', updatedAt: Date.now() });
    await pubsub.topic(topic).publishMessage({ json: { jobId } });

    res.json({ jobId, status: 'queued' });
  });

  // 3) Poll job
  router.get('/ingest/:jobId', async (req, res) => {
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
