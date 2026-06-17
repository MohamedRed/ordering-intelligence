import express from 'express';
import type { AppContext } from '../app.js';

type MenuItemInput = {
  id: string;
  name: string;
  priceCents: number;
  available?: boolean;
  category?: string;
  modifiers?: Array<{ name: string; priceCents: number }>;
  modifierGroups?: Array<Record<string, unknown>>;
  description?: string;
};

const buildDefaultMenu = (storeId: string) => ({
  storeId,
  items: [
    {
      id: 'ci-item-1',
      name: 'CI Test Item',
      priceCents: 990,
      available: true,
      category: 'Test',
      modifiers: [],
      description: 'CI menu item',
    },
  ],
  bundleRules: [],
});

const normalizeMenuItem = (item: MenuItemInput): MenuItemInput => ({
  id: String(item.id || '').trim(),
  name: String(item.name || '').trim(),
  priceCents: Number(item.priceCents || 0),
  available: item.available !== false,
  category: String(item.category || 'General').trim(),
  modifiers: Array.isArray(item.modifiers) ? item.modifiers : [],
  modifierGroups: Array.isArray(item.modifierGroups) ? item.modifierGroups : [],
  description: String(item.description || '').trim(),
});

export const testRouter = (ctx: AppContext) => {
  const router = express.Router();

  router.post('/internal/test/menu-update', ctx.requireAuth, async (req, res) => {
    try {
      const storeId = String(req.body?.storeId || '').trim();
      if (!storeId) {
        return res.status(400).json({ error: 'missing_store_id' });
      }
      const jobId = String(req.body?.jobId || '').trim();
      const source = String(req.body?.source || 'internal_test').trim();

      const inputMenu = req.body?.menu ?? {};
      const items = Array.isArray(inputMenu.items) ? inputMenu.items.map(normalizeMenuItem) : [];
      const menuRecord = {
        storeId,
        items: items.length > 0 ? items : buildDefaultMenu(storeId).items,
        bundleRules: Array.isArray(inputMenu.bundleRules) ? inputMenu.bundleRules : [],
        updatedAt: new Date(),
      };

      await ctx.firestore.collection('menus').doc(storeId).set(menuRecord, { merge: true });

      if (ctx.menuUpdatesTopic) {
        const updatePayload: Record<string, unknown> = {
          storeId,
          updatedAt: new Date().toISOString(),
          status: 'completed',
          source,
        };
        if (jobId) updatePayload.jobId = jobId;

        await ctx.pubsub.topic(ctx.menuUpdatesTopic).publishMessage({
          json: updatePayload,
        });
      }

      return res.json({ ok: true, storeId });
    } catch (err: any) {
      console.error('menu test hook failed', err);
      return res.status(500).json({ error: 'menu_test_failed', message: err?.message ?? String(err) });
    }
  });

  return router;
};
