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

jest.mock('@google-cloud/storage', () => ({
  Storage: class Storage {
    bucket() {
      return {
        file: () => ({
          download: async () => [Buffer.from('agent-output')],
        }),
      };
    }
  },
}));

jest.mock('@google-cloud/vertexai', () => ({
  VertexAI: class VertexAI {
    getGenerativeModel() {
      return {};
    }
  },
}));

jest.mock('google-auth-library', () => ({
  GoogleAuth: class GoogleAuth {
    getAccessToken() {
      return Promise.resolve('token');
    }
  },
}));

// Minimal fetch mock
const fetchMock = jest.fn();
(global as any).fetch = fetchMock;

let geminiJson: typeof import('../../src/services/generation').geminiJson;

beforeAll(async () => {
  const module = await import('../../src/services/generation');
  geminiJson = module.geminiJson;
});

beforeEach(() => {
  jest.clearAllMocks();
  // Default: Vertex returns 429
  (fetchMock as jest.Mock).mockResolvedValue({
    ok: false,
    status: 429,
    statusText: 'Too Many Requests',
    headers: { get: () => 'application/json' },
    text: async () => '{"error":"rate"}',
  });
});

describe('geminiJson fallback', () => {
  it('enqueues agent job on 429 and returns agent JSON text', async () => {
    (enqueueAgentJobMock as jest.Mock).mockResolvedValue('doc-1');
    (waitForAgentJobMock as jest.Mock).mockResolvedValue({ outputText: '{"foo":123}' });

    const result = await geminiJson('p', 'gs://b/o', 'image/png', 'model-x', 'test-label');

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(enqueueAgentJobMock).toHaveBeenCalledWith(
      'test-label',
      'p',
      'gs://b/o',
      'image/png',
      'model-x',
      expect.any(String),
    );
    expect(waitForAgentJobMock).toHaveBeenCalledWith('doc-1', 'test-label');
    expect(result).toEqual({ foo: 123 });
  });

  it('returns undefined when agent job produces no usable output', async () => {
    (enqueueAgentJobMock as jest.Mock).mockResolvedValue('doc-2');
    (waitForAgentJobMock as jest.Mock).mockResolvedValue({ outputText: undefined, outputPath: undefined });
    await expect(geminiJson('p', 'gs://b/o', 'image/png', 'model-x', 'lbl')).rejects.toBeTruthy();
  });
});
