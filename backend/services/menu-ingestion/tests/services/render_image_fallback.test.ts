// @ts-nocheck
import { jest } from '@jest/globals';

process.env.MENU_BUCKET = 'test-bucket';
process.env.GOOGLE_CLOUD_PROJECT = 'test-project';
process.env.VERTEX_PROJECT = 'test-project';

const enqueueAgentJobMock = jest.fn();
const waitForAgentJobMock = jest.fn();

jest.mock('../../src/services/agent_queue', () => ({
  enqueueAgentJob: (...args: any[]) => enqueueAgentJobMock(...args),
  waitForAgentJob: (...args: any[]) => waitForAgentJobMock(...args),
}));

const fetchMock = jest.fn();
(global as any).fetch = fetchMock;

let renderImage: typeof import('../../src/services/generation').renderImage;

beforeAll(async () => {
  const mod = await import('../../src/services/generation');
  renderImage = mod.renderImage;
});

beforeEach(() => {
  jest.clearAllMocks();
  fetchMock.mockResolvedValue({
    status: 429,
    ok: false,
    statusText: 'Too Many Requests',
    text: async () => '{"error":"rate"}',
  });
});

describe('renderImage fallback', () => {
  it('enqueues agent job on 429 and returns agent image', async () => {
    enqueueAgentJobMock.mockResolvedValue('doc-1');
    waitForAgentJobMock.mockResolvedValue({ outputB64: Buffer.from('hi').toString('base64') });

    const res = await renderImage({
      prompt: 'p',
      mimeType: 'image/png',
      modelId: 'm1',
      label: 'render',
      fileUri: 'gs://b/o',
    });

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(enqueueAgentJobMock).toHaveBeenCalledWith(
      'render',
      'p',
      'gs://b/o',
      'image/png',
      'm1',
      'render-o',
    );
    expect(waitForAgentJobMock).toHaveBeenCalledWith('doc-1', 'render');
    expect(res).toBe(Buffer.from('hi').toString('base64'));
  });
});
