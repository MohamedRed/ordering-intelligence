import type { Express, Response } from 'express';
import { FieldValue, Timestamp, type CollectionReference } from '@google-cloud/firestore';

type MenuFlyerSession = {
  flyers?: string[];
};

type RegisterMenuFlyerSessionRoutesParams = {
  app: Express;
  sessions: CollectionReference;
  getSession: (id: string, res: Response) => Promise<(MenuFlyerSession & { id: string }) | null>;
  audit: (id: string, event: string, data?: unknown) => Promise<void>;
};

type FlyerAction = 'attach' | 'detach';

export function registerMenuFlyerSessionRoutes(params: RegisterMenuFlyerSessionRoutesParams): void {
  params.app.patch('/onboarding-sessions/:id/menu-flyers', async (req, res) => {
    await updateSessionFlyers(params, req.params.id, req.body?.urls, 'attach', res);
  });

  params.app.delete('/onboarding-sessions/:id/menu-flyers', async (req, res) => {
    await updateSessionFlyers(params, req.params.id, req.body?.urls, 'detach', res);
  });
}

function validateFlyerUrls(urls: unknown): string[] | undefined {
  if (!Array.isArray(urls) || urls.length === 0) return undefined;
  return urls.map((url) => String(url).trim()).filter(Boolean);
}

async function updateSessionFlyers(
  params: RegisterMenuFlyerSessionRoutesParams,
  sessionId: string,
  urlsRaw: unknown,
  action: FlyerAction,
  res: Response,
): Promise<void> {
  const urls = validateFlyerUrls(urlsRaw);
  if (!urls?.length) {
    res.status(400).json({ error: 'urls_required' });
    return;
  }

  try {
    const snap = await params.getSession(sessionId, res);
    if (!snap) return;

    await params.sessions.doc(sessionId).update({
      flyers: action === 'attach' ? FieldValue.arrayUnion(...urls) : FieldValue.arrayRemove(...urls),
      updated_at: Timestamp.now(),
    });
    await params.audit(sessionId, action === 'attach' ? 'flyers_attached' : 'flyers_detached', { urls });
    res.json({ ok: true });
  } catch (err: any) {
    const label = action === 'attach' ? 'menu-flyers' : 'menu-flyers delete';
    console.error(`${label} error`, err);
    res.status(500).json({
      error: action === 'attach' ? 'flyers_failed' : 'flyers_delete_failed',
      message: err.message,
    });
  }
}
