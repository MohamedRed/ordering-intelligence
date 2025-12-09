import { jest } from '@jest/globals';

process.env.AGENT_QUEUE_COLLECTION = 'agent_jobs';

type DocumentData = { status?: string };

const docs = new Map<string, DocumentData>();
const setSpy = jest.fn();

class Document {
  constructor(private id: string) {}
  async get() {
    const data = docs.get(this.id);
    return { exists: !!data, data: () => data };
  }
  async set(payload: DocumentData) {
    setSpy(payload);
    docs.set(this.id, payload);
  }
  async update(update: DocumentData) {
    const existing = docs.get(this.id) ?? {};
    const merged = { ...existing, ...update };
    docs.set(this.id, merged);
  }
}

class Firestore {
  collection() {
    return this;
  }
  doc(id: string) {
    return new Document(id);
  }
}

jest.mock('@google-cloud/firestore', () => ({
  Firestore,
  __agentQueueState: {
    reset: () => {
      docs.clear();
      setSpy.mockClear();
    },
  },
  __agentQueueDocs: docs,
  __agentQueueSetSpy: setSpy,
}));

let enqueueAgentJob: typeof import('../../src/services/agent_queue').enqueueAgentJob;
let __agentQueueState: any;
let __agentQueueSetSpy: jest.Mock;
let __agentQueueDocs: Map<string, any>;

beforeAll(async () => {
  const agentModule = await import('../../src/services/agent_queue');
  enqueueAgentJob = agentModule.enqueueAgentJob;
  const firestoreModule = (await import('@google-cloud/firestore')) as any;
  __agentQueueState = firestoreModule.__agentQueueState;
  __agentQueueSetSpy = firestoreModule.__agentQueueSetSpy;
  __agentQueueDocs = firestoreModule.__agentQueueDocs;
});

describe('agent_queue', () => {
  beforeEach(() => {
    __agentQueueState.reset();
  });

  it('reuses existing doc when status is not error', async () => {
    const docId = 'same-doc';
    await enqueueAgentJob('label', 'prompt', 'file', 'mime', 'model', docId);
    expect(__agentQueueSetSpy).toHaveBeenCalledTimes(1);

    const result = await enqueueAgentJob('label', 'prompt', 'file', 'mime', 'model', docId);
    expect(result).toBe(docId);
    expect(__agentQueueSetSpy).toHaveBeenCalledTimes(1);
  });

  it('retries when existing doc is error', async () => {
    const docId = 'error-doc';
    await enqueueAgentJob('label', 'prompt', 'file', 'mime', 'model', docId);
    __agentQueueDocs.set(docId, { status: 'error' });

    await enqueueAgentJob('label', 'prompt', 'file', 'mime', 'model', docId);
    expect(__agentQueueSetSpy).toHaveBeenCalledTimes(2);
  });

  it('analysis label reuses doc when already present', async () => {
    const docId = 'analysis-same';
    await enqueueAgentJob('analysis', 'prompt', 'file', 'mime', 'model', docId);
    expect(__agentQueueSetSpy).toHaveBeenCalledTimes(1);
    const again = await enqueueAgentJob('analysis', 'prompt', 'file', 'mime', 'model', docId);
    expect(again).toBe(docId);
    expect(__agentQueueSetSpy).toHaveBeenCalledTimes(1);
  });

  it('analysis label re-enqueues if status error', async () => {
    const docId = 'analysis-error';
    await enqueueAgentJob('analysis', 'prompt', 'file', 'mime', 'model', docId);
    __agentQueueDocs.set(docId, { status: 'error' });

    await enqueueAgentJob('analysis', 'prompt', 'file', 'mime', 'model', docId);
    expect(__agentQueueSetSpy).toHaveBeenCalledTimes(2);
  });

  it('composite docIds are unique per page and reused', async () => {
    const jobId = 'job-xyz';
    const label = 'composite';
    const docId = `composite-${jobId}-p1`;
    await enqueueAgentJob(label, 'prompt', 'file', 'mime', 'model', docId);
    expect(__agentQueueSetSpy).toHaveBeenCalledTimes(1);
    const again = await enqueueAgentJob(label, 'prompt', 'file', 'mime', 'model', docId);
    expect(again).toBe(docId);
    expect(__agentQueueSetSpy).toHaveBeenCalledTimes(1);
    const nextDocId = `composite-${jobId}-p2`;
    await enqueueAgentJob(label, 'prompt', 'file', 'mime', 'model', nextDocId);
    expect(__agentQueueSetSpy).toHaveBeenCalledTimes(2);
  });
});
