import express from 'express';
import type { AppContext } from '../app.js';
import type { IngestJob } from '../types.js';

export function cleanupRouter(ctx: AppContext) {
  const router = express.Router();
  const { firestore } = ctx;

  router.post('/tasks/cleanup', ctx.requireAuth, async (_req, res) => {
    const now = Date.now();
    // Avoid composite index requirement: query by expiry time then filter status in memory.
    const snap = await firestore
      .collection('menus_ingest')
      .where('processingExpiresAt', '<', now)
      .limit(200)
      .get();

    const batch = firestore.batch();
    let count = 0;
    snap.forEach((doc) => {
      const data = doc.data() as IngestJob;
      if (data.status !== 'processing') return;
      batch.update(doc.ref, {
        status: 'queued',
        updatedAt: now,
        issues: (data.issues ?? []).concat('reset by cleanup'),
      });
      count += 1;
    });
    if (count > 0) await batch.commit();
    res.json({ reset: count });
  });

  return router;
}
