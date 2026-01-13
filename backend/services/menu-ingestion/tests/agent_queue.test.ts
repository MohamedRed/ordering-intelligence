import { enqueueAgentJob, waitForAgentJob } from '../src/services/agent_queue';

// In-memory Firestore mock
const store = new Map<string, any>();
jest.mock('@google-cloud/firestore', () => {
  return {
    Firestore: class {
      collection() {
        return {
          doc: (id: string) => ({
            get: async () => {
              const data = store.get(id);
              return {
                exists: data !== undefined,
                data: () => data,
              };
            },
            set: async (data: any) => {
              store.set(id, data);
            },
          }),
        };
      }
    },
  };
});

// Force fast waits
jest.mock('../src/config.js', () => ({
  AGENT_QUEUE_COLLECTION: 'agent_queue',
  AGENT_QUEUE_WAIT_MS: 30,
}));

// Skip real sleeping
jest.mock('../src/utils.js', () => ({
  delay: jest.fn(async () => {}),
}));

describe('agent_queue', () => {
  beforeEach(() => {
    store.clear();
  });

  it('enqueues new job', async () => {
    const id = await enqueueAgentJob('label', 'prompt', 'gs://file', 'image/png', 'model', 'job1');
    expect(id).toBe('job1');
    expect(store.has('job1')).toBe(true);
  });

  it('returns existing job if already queued', async () => {
    store.set('job1', { status: 'queued' });
    const id = await enqueueAgentJob('label', 'prompt', 'gs://file', 'image/png', 'model', 'job1');
    expect(id).toBe('job1');
  });

  it('waits for completion and returns output', async () => {
    store.set('job1', { status: 'done', outputText: 'ok' });
    const res = await waitForAgentJob('job1', 'label');
    expect(res?.outputText).toBe('ok');
  });

  it('stops on error status', async () => {
    store.set('job1', { status: 'error', error: 'fail' });
    const res = await waitForAgentJob('job1', 'label');
    expect(res).toBeUndefined();
  });

  it('stops on canceled status', async () => {
    store.set('job1', { status: 'canceled' });
    const res = await waitForAgentJob('job1', 'label');
    expect(res).toBeUndefined();
  });

  it('times out when doc missing', async () => {
    const res = await waitForAgentJob('missing', 'label');
    expect(res).toBeUndefined();
  });
});
