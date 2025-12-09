import express from 'express';
import type { AppContext } from '../app.js';

export function agentRouter(ctx: AppContext) {
  const router = express.Router();
  const { firestore, requireAuth } = ctx;

  router.get('/agent-jobs', requireAuth, async (_req, res) => {
    const snap = await firestore
      .collection(process.env.AGENT_QUEUE_COLLECTION || 'agent_jobs')
      .orderBy('createdAt', 'desc')
      .limit(50)
      .get();
    const jobs = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    res.json({ jobs });
  });

  router.get('/agent-worker/config', requireAuth, async (_req, res) => {
    const docId = process.env.AGENT_CONFIG_DOC || 'agent_worker/config';
    const doc = await firestore.doc(docId).get();
    const cfg = doc.exists ? doc.data() : { enabled: false };
    res.json(cfg);
  });

  router.post('/agent-worker/config', requireAuth, async (req, res) => {
    const docId = process.env.AGENT_CONFIG_DOC || 'agent_worker/config';
    const enabled = Boolean(req.body?.enabled);
    await firestore.doc(docId).set({ enabled, updatedAt: Date.now() }, { merge: true });
    res.json({ enabled });
  });

  return router;
}
