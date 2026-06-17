import type { Express, Response } from 'express';
import { Timestamp, type CollectionReference, type Firestore } from '@google-cloud/firestore';
import type { Bucket } from '@google-cloud/storage';
import type { PubSub } from '@google-cloud/pubsub';
import { v4 as uuidv4 } from 'uuid';
import { validateMenuFlyerCount } from './menu_ingestion_limits.js';
import { resolveMenuFlyerMediaFromUrl } from './menu_flyer_media.js';

type MenuIngestionSession = {
  flyers?: string[];
  tenant?: {
    tenant_id?: string;
    store_id?: string;
  };
  ingestion?: {
    job_ids?: string[];
    fast_ready?: boolean;
  };
};

type RegisterMenuIngestionRoutesParams = {
  app: Express;
  firestore: Firestore;
  sessions: CollectionReference;
  pubsub: PubSub;
  bucket: Bucket;
  bucketName: string;
  menuIngestTopic: string;
  getSession: (id: string, res: Response) => Promise<(MenuIngestionSession & { id: string }) | null>;
  audit: (id: string, event: string, data?: unknown) => Promise<void>;
};

export type BucketObjectRef = { bucket?: string; key?: string };
export type MenuPipelineMode = 'full' | 'menu_only';

class MenuIngestionRouteError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'MenuIngestionRouteError';
  }
}

export function registerMenuIngestionRoutes(params: RegisterMenuIngestionRoutesParams): void {
  params.app.post('/onboarding-sessions/:id/ingest-menu', async (req, res) => {
    try {
      const { id } = req.params;
      const snap = await params.getSession(id, res);
      if (!snap) return;

      const flyers = (snap.flyers ?? []).filter(Boolean);
      if (!flyers.length) {
        return res.status(400).json({ error: 'no_flyers' });
      }
      const flyerLimitError = validateMenuFlyerCount(flyers.length);
      if (flyerLimitError) {
        return res.status(400).json({ error: 'too_many_flyers', message: flyerLimitError });
      }

      const mode = resolveMenuPipelineMode(req.body?.mode);
      const restaurantId = resolveRestaurantId(snap, id);
      const jobId = uuidv4();
      const nowMs = Date.now();
      const files = await copyFlyersToMenuRawPath({
        bucket: params.bucket,
        bucketName: params.bucketName,
        restaurantId,
        jobId,
        flyers,
      });

      await params.firestore.collection('menus_ingest').doc(jobId).set({
        jobId,
        restaurantId,
        status: 'queued',
        pipelineMode: mode,
        files,
        createdAt: nowMs,
        updatedAt: nowMs,
      });

      await params.pubsub.topic(params.menuIngestTopic).publishMessage({ json: { jobId } });

      await params.sessions.doc(id).update({
        ingestion: { job_ids: [jobId], status: 'queued', fast_ready: false },
        updated_at: Timestamp.now(),
      });
      await params.audit(id, 'ingest_triggered', { jobId, restaurantId, fileCount: files.length });
      return res.json({ job_id: jobId });
    } catch (err: any) {
      if (err instanceof MenuIngestionRouteError) {
        return res.status(err.statusCode).json({ error: err.code, message: err.message });
      }
      console.error('ingest-menu error', err);
      return res.status(500).json({ error: 'ingest_failed', message: err.message });
    }
  });

  params.app.post('/onboarding-sessions/:id/ingest-menu/resume-images', async (req, res) => {
    try {
      const { id } = req.params;
      const snap = await params.getSession(id, res);
      if (!snap) return;
      const jobIds = snap.ingestion?.job_ids || [];
      if (!jobIds.length) {
        return res.status(400).json({ error: 'no_ingest_job' });
      }

      const jobId = jobIds[jobIds.length - 1] as string;
      const nowMs = Date.now();
      await params.firestore.collection('menus_ingest').doc(jobId).set(
        {
          jobId,
          status: 'queued',
          pipelineMode: 'full',
          resumeRequestedAt: nowMs,
          progressStage: 'queued',
          progressPercent: 0,
          updatedAt: nowMs,
        },
        { merge: true },
      );

      await params.pubsub.topic(params.menuIngestTopic).publishMessage({ json: { jobId } });

      await params.sessions.doc(id).update({
        ingestion: { job_ids: jobIds, status: 'queued', fast_ready: snap.ingestion?.fast_ready ?? false },
        updated_at: Timestamp.now(),
      });
      await params.audit(id, 'ingest_resume_images_triggered', { jobId });
      return res.json({ job_id: jobId });
    } catch (err: any) {
      console.error('ingest-menu resume-images error', err);
      return res.status(500).json({ error: 'ingest_resume_images_failed', message: err.message });
    }
  });

  params.app.post('/onboarding-sessions/:id/cancel-ingest', async (req, res) => {
    try {
      const { id } = req.params;
      const snap = await params.getSession(id, res);
      if (!snap) return;
      const jobIds = snap.ingestion?.job_ids || [];
      if (!jobIds.length) {
        return res.json({ ok: true, canceled: 0 });
      }

      const nowMs = Date.now();
      const batch = params.firestore.batch();
      for (const jobId of jobIds) {
        batch.set(
          params.firestore.collection('menus_ingest').doc(jobId),
          {
            status: 'canceled',
            cancelRequestedAt: nowMs,
            progressStage: 'canceled',
            progressPercent: 100,
            updatedAt: nowMs,
          },
          { merge: true },
        );
      }
      await batch.commit();

      await params.sessions.doc(id).update({
        ingestion: { job_ids: jobIds, status: 'canceled' },
        updated_at: Timestamp.now(),
      });
      await params.audit(id, 'ingest_canceled', { jobIds });
      return res.json({ ok: true, canceled: jobIds.length });
    } catch (err: any) {
      console.error('cancel-ingest error', err);
      return res.status(500).json({ error: 'cancel_ingest_failed', message: err.message });
    }
  });
}

export function resolveMenuPipelineMode(modeRaw: unknown): MenuPipelineMode {
  const mode = modeRaw ?? 'full';
  return mode === 'full' || mode === 'menu_only' ? mode : 'menu_only';
}

export function extractBucketKeyFromUrl(url: string): BucketObjectRef {
  try {
    const parsed = new URL(url);
    if (parsed.hostname === 'storage.googleapis.com') {
      const parts = parsed.pathname.split('/').filter(Boolean);
      if (parts.length >= 2) {
        return { bucket: parts[0], key: parts.slice(1).join('/') };
      }
    }
    if (parsed.hostname.endsWith('.storage.googleapis.com')) {
      const bucket = parsed.hostname.split('.')[0];
      const key = parsed.pathname.startsWith('/') ? parsed.pathname.slice(1) : parsed.pathname;
      return { bucket, key: key || undefined };
    }
  } catch {
    return {};
  }
  return {};
}

function resolveRestaurantId(session: MenuIngestionSession, sessionId: string): string {
  return (
    (session.tenant?.store_id || '').trim() ||
    (session.tenant?.tenant_id || '').trim() ||
    `store_${sessionId}`
  );
}

async function copyFlyersToMenuRawPath(params: {
  bucket: Bucket;
  bucketName: string;
  restaurantId: string;
  jobId: string;
  flyers: string[];
}): Promise<string[]> {
  const files: string[] = [];
  for (let i = 0; i < params.flyers.length; i += 1) {
    const parsed = extractBucketKeyFromUrl(params.flyers[i]);
    const media = resolveMenuFlyerMediaFromUrl(parsed.key ?? params.flyers[i]);
    if (!media) {
      throw new MenuIngestionRouteError(
        400,
        'unsupported_menu_flyer_type',
        'Menu flyer URLs must point to JPEG, PNG, or WebP images.',
      );
    }
    const dest = `menu-raw/${params.restaurantId}/${params.jobId}/page-${i + 1}.${media.extension}`;
    const buffer = await readFlyerBytes(params.bucket, params.bucketName, params.flyers[i], parsed);
    await params.bucket.file(dest).save(buffer, { contentType: media.contentType, resumable: false });
    files.push(dest);
  }
  return files;
}

async function readFlyerBytes(
  bucket: Bucket,
  bucketName: string,
  flyerUrl: string,
  parsed: BucketObjectRef,
): Promise<Buffer> {
  if (parsed.bucket === bucketName && parsed.key) {
    const [buffer] = await bucket.file(parsed.key).download();
    return buffer;
  }

  const resp = await fetch(flyerUrl);
  if (!resp.ok) {
    throw new Error(`flyer_fetch_failed status=${resp.status}`);
  }
  return Buffer.from(await resp.arrayBuffer());
}
