import type { Express, Response } from 'express';
import { Timestamp, type CollectionReference, type Firestore } from '@google-cloud/firestore';

type AgentCreationSession = {
  ingestion?: {
    status?: string;
    fast_ready?: boolean;
    job_ids?: string[];
  };
  business?: {
    type?: string;
  };
  agent?: {
    template_agent_id?: string;
    agent_id?: string;
  };
};

type RegisterAgentCreationRoutesParams = {
  app: Express;
  firestore: Firestore;
  sessions: CollectionReference;
  getSession: (id: string, res: Response) => Promise<(AgentCreationSession & { id: string }) | null>;
  audit: (id: string, event: string, data?: unknown) => Promise<void>;
  resolveTemplateAgentId: (businessTypeRaw: string) => string;
};

export function registerAgentCreationRoutes(params: RegisterAgentCreationRoutesParams): void {
  params.app.post('/onboarding-sessions/:id/create-agent', async (req, res) => {
    try {
      const { id } = req.params;
      const snap = await params.getSession(id, res);
      if (!snap) return;

      const existingResponse = resolveExistingAgentResponse(snap);
      if (existingResponse) return res.json(existingResponse);

      const ready = await isIngestionReadyForAgent(params.firestore, snap);
      if (!ready) {
        return res.status(400).json({ error: 'ingestion_not_ready', status: snap.ingestion?.status || null });
      }

      const businessType = resolveBusinessType(snap);
      const templateAgentId = params.resolveTemplateAgentId(businessType);
      if (!templateAgentId) {
        return res.status(500).json({ error: 'elevenlabs_template_not_configured', business_type: businessType });
      }

      await params.sessions.doc(id).update({
        agent: {
          mode: 'shared_template',
          template_agent_id: templateAgentId,
          business_type: businessType,
          status: 'configured',
        },
        updated_at: Timestamp.now(),
      });
      await params.audit(id, 'agent_created', {
        template_agent_id: templateAgentId,
        business_type: businessType,
        mode: 'shared_template',
      });

      return res.json({
        reused: false,
        agent_mode: 'shared_template',
        template_agent_id: templateAgentId,
        agent_id: templateAgentId,
      });
    } catch (err: any) {
      console.error('create-agent error', err);
      return res.status(500).json({ error: 'agent_create_failed', message: err.message });
    }
  });
}

function resolveExistingAgentResponse(session: AgentCreationSession):
  | {
      reused: true;
      agent_mode: 'shared_template' | 'per_tenant';
      template_agent_id: string | null;
      agent_id: string | undefined;
    }
  | null {
  const existingAgentId = session.agent?.agent_id;
  const existingTemplateId = session.agent?.template_agent_id;
  if (!existingTemplateId && !existingAgentId) return null;
  return {
    reused: true,
    agent_mode: existingTemplateId ? 'shared_template' : 'per_tenant',
    template_agent_id: existingTemplateId ?? null,
    agent_id: existingTemplateId ?? existingAgentId,
  };
}

async function isIngestionReadyForAgent(
  firestore: Firestore,
  session: AgentCreationSession,
): Promise<boolean> {
  const ingestStatus = (session.ingestion?.status || '').toLowerCase();
  const readyByStatus = ['succeeded', 'partial_ok'].includes(ingestStatus);
  if (readyByStatus || session.ingestion?.fast_ready) return true;

  const jobIds = session.ingestion?.job_ids || [];
  const jobId = jobIds.length ? jobIds[jobIds.length - 1] : null;
  if (!jobId) return false;

  if (await hasReadyIngestJob(firestore, jobId)) return true;
  return hasMenuDraft(firestore, jobId);
}

async function hasReadyIngestJob(firestore: Firestore, jobId: string): Promise<boolean> {
  try {
    const jobSnap = await firestore.collection('menus_ingest').doc(jobId).get();
    const job = jobSnap.exists ? (jobSnap.data() as any) : null;
    const kind = (job?.readyKind ?? '').toLowerCase();
    return kind === 'menu_only' || kind === 'full';
  } catch {
    return false;
  }
}

async function hasMenuDraft(firestore: Firestore, jobId: string): Promise<boolean> {
  try {
    const draftSnap = await firestore.collection('menus_drafts').doc(jobId).get();
    return draftSnap.exists;
  } catch {
    return false;
  }
}

function resolveBusinessType(session: AgentCreationSession): string {
  return ((session.business?.type || '').trim() || 'fast_food').toLowerCase();
}
