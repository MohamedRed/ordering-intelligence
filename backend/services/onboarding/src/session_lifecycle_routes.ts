import type { Express, Response } from 'express';
import { Timestamp, type CollectionReference } from '@google-cloud/firestore';
import { v4 as uuidv4 } from 'uuid';

type SessionStatus = 'collecting' | 'prefill_ready' | 'awaiting_kyc' | 'ingesting' | 'ready' | 'failed';

type LifecycleSession = {
  status?: SessionStatus;
  business?: Record<string, unknown>;
  flyers?: string[];
  audit?: unknown[];
  tenant?: {
    tenant_id?: string;
    store_id?: string;
  };
};

type TenantState = {
  active_session_id?: string;
  last_session_id?: string;
  store_id?: string;
};

type RegisterSessionLifecycleRoutesParams = {
  app: Express;
  sessions: CollectionReference;
  tenants: CollectionReference;
  getSession: (id: string, res: Response) => Promise<(LifecycleSession & { id: string }) | null>;
  audit: (id: string, event: string, data?: unknown) => Promise<void>;
  createSessionId?: () => string;
};

export function registerSessionLifecycleRoutes(params: RegisterSessionLifecycleRoutesParams): void {
  params.app.get('/onboarding-tenants/:tenantId', async (req, res) => {
    try {
      const tenantId = (req.params.tenantId || '').trim();
      if (!tenantId) return res.status(400).json({ error: 'tenant_id_required' });

      const tenantSnap = await params.tenants.doc(tenantId).get();
      if (!tenantSnap.exists) {
        return res.status(404).json({ error: 'tenant_not_found' });
      }

      const tenantState = tenantSnap.data() as TenantState;
      const activeId = tenantState.active_session_id;
      let session: any = null;
      if (activeId) {
        const sessionSnap = await params.sessions.doc(activeId).get();
        if (sessionSnap.exists) {
          session = { session_id: activeId, ...(sessionSnap.data() as LifecycleSession) };
        }
      }

      return res.json({
        tenant_id: tenantId,
        active_session_id: activeId ?? null,
        last_session_id: tenantState.last_session_id ?? null,
        store_id: tenantState.store_id ?? null,
        session,
      });
    } catch (err: any) {
      console.error('tenant status error', err);
      return res.status(500).json({ error: 'tenant_status_failed', message: err.message });
    }
  });

  params.app.post('/onboarding-sessions', async (req, res) => {
    try {
      const tenantId = (req.body?.tenant_id as string | undefined)?.trim();
      const storeId = (req.body?.store_id as string | undefined)?.trim();

      const reusableSessionId = tenantId ? await resolveReusableSessionId(params, tenantId) : null;
      if (reusableSessionId) {
        return res.status(201).json({ session_id: reusableSessionId, reused: true });
      }

      const id = (params.createSessionId ?? uuidv4)();
      const now = Timestamp.now();
      const doc = {
        status: 'collecting',
        business: {},
        flyers: [],
        audit: [],
        tenant: tenantId ? { tenant_id: tenantId, store_id: storeId } : undefined,
        created_at: now,
        updated_at: now,
      };

      await params.sessions.doc(id).set(doc);
      await params.audit(id, 'session_created', tenantId ? { tenant_id: tenantId, store_id: storeId } : undefined);

      if (tenantId) {
        await params.tenants.doc(tenantId).set(
          {
            active_session_id: id,
            last_session_id: id,
            store_id: storeId,
            created_at: now,
            updated_at: now,
          },
          { merge: true },
        );
      }

      return res.status(201).json({ session_id: id, reused: false });
    } catch (err: any) {
      console.error('create session error', err);
      return res.status(500).json({ error: 'session_create_failed', message: err.message });
    }
  });

  params.app.post('/onboarding-sessions/:id/notifications', async (req, res) => {
    try {
      const { id } = req.params;
      const { device_tokens = [], webhook_url } = req.body || {};
      const snap = await params.getSession(id, res);
      if (!snap) return;

      await params.sessions.doc(id).update({
        notifications: {
          device_tokens,
          webhook_url,
        },
        updated_at: Timestamp.now(),
      });
      await params.audit(id, 'notifications_set', { device_tokens, webhook_url });
      return res.json({ ok: true });
    } catch (err: any) {
      console.error('notifications error', err);
      return res.status(500).json({ error: 'notifications_failed', message: err.message });
    }
  });
}

async function resolveReusableSessionId(
  params: RegisterSessionLifecycleRoutesParams,
  tenantId: string,
): Promise<string | null> {
  const tenantDocRef = params.tenants.doc(tenantId);
  const tenantSnap = await tenantDocRef.get();
  const tenantState = (tenantSnap.exists ? (tenantSnap.data() as TenantState) : null) ?? null;
  const activeId = tenantState?.active_session_id;
  if (!activeId) return null;

  const activeSnap = await params.sessions.doc(activeId).get();
  if (!activeSnap.exists) return null;

  const active = activeSnap.data() as LifecycleSession;
  return active.status !== 'ready' && active.status !== 'failed' ? activeId : null;
}
