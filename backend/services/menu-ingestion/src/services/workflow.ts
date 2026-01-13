import { Firestore } from '@google-cloud/firestore';

const firestore = new Firestore({ ignoreUndefinedProperties: true });

// Firestore can occasionally stall on network/transient issues; never let workflow logging hang ingestion.
const WORKFLOW_IO_TIMEOUT_MS = Number(process.env.WORKFLOW_IO_TIMEOUT_MS ?? 5000);

async function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  let timeout: NodeJS.Timeout;
  const wrapped = new Promise<never>((_, reject) => {
    timeout = setTimeout(() => reject(new Error(`timeout after ${ms}ms`)), ms);
  });
  try {
    return await Promise.race([promise, wrapped]);
  } finally {
    clearTimeout(timeout!);
  }
}

export type WorkflowNodeStatus =
  | 'queued'
  | 'running'
  | 'succeeded'
  | 'error'
  | 'canceled'
  | 'skipped';

export interface WorkflowNode {
  id: string;
  parentId?: string | null;
  kind: string;
  label: string;
  status: WorkflowNodeStatus;
  seq?: number;
  page?: number;
  itemIndex?: number;
  modelId?: string;
  fileUri?: string;
  startedAt?: number;
  endedAt?: number;
  error?: string;
  meta?: Record<string, any>;
  updatedAt?: number;
}

function nodesCollection(jobId: string) {
  return firestore.collection('menus_ingest').doc(jobId).collection('workflow_nodes');
}

export async function ensureWorkflowRoot(jobId: string, restaurantId?: string) {
  try {
    await withTimeout(
      nodesCollection(jobId).doc('root').set(
      {
        id: 'root',
        parentId: null,
        kind: 'root',
        label: restaurantId ? `Ingest ${restaurantId}` : 'Ingest',
        status: 'running',
        seq: 0,
        updatedAt: Date.now(),
      } as WorkflowNode,
      { merge: true },
      ),
      WORKFLOW_IO_TIMEOUT_MS,
    );
  } catch {
    // Best-effort; ignore failures.
  }
}

export async function startWorkflowNode(jobId: string, node: Omit<WorkflowNode, 'status'> & { status?: WorkflowNodeStatus }) {
  try {
    const now = Date.now();
    await withTimeout(
      nodesCollection(jobId).doc(node.id).set(
      {
        ...node,
        status: node.status ?? 'running',
        startedAt: node.startedAt ?? now,
        updatedAt: now,
      } as WorkflowNode,
      { merge: true },
      ),
      WORKFLOW_IO_TIMEOUT_MS,
    );
  } catch {
    // Best-effort; ignore failures.
  }
}

export async function finishWorkflowNode(jobId: string, nodeId: string, updates?: Partial<WorkflowNode>) {
  try {
    const now = Date.now();
    await withTimeout(
      nodesCollection(jobId).doc(nodeId).set(
      {
        ...(updates ?? {}),
        id: nodeId,
        status: updates?.status ?? 'succeeded',
        endedAt: updates?.endedAt ?? now,
        updatedAt: now,
      } as WorkflowNode,
      { merge: true },
      ),
      WORKFLOW_IO_TIMEOUT_MS,
    );
  } catch {
    // Best-effort; ignore failures.
  }
}

export async function failWorkflowNode(jobId: string, nodeId: string, err: unknown, updates?: Partial<WorkflowNode>) {
  const message = err instanceof Error ? err.message : String(err);
  await finishWorkflowNode(jobId, nodeId, {
    ...(updates ?? {}),
    status: 'error',
    error: message,
  });
}

export async function skipWorkflowNode(jobId: string, nodeId: string, reason: string, updates?: Partial<WorkflowNode>) {
  await finishWorkflowNode(jobId, nodeId, {
    ...(updates ?? {}),
    status: 'skipped',
    error: reason,
  });
}
