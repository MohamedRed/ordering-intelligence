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

// mock Storage for signed URL
jest.mock('@google-cloud/storage', () => ({
  Storage: class Storage {
    bucket() {
      return {
        file: () => ({
          getSignedUrl: async () => ['http://signed'],
        }),
      };
    }
  },
}));

jest.mock('@google-cloud/firestore', () => ({
  Firestore: class Firestore {
    collection() {
      return { doc: () => ({}) };
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

const fetchMock = jest.fn();
(global as any).fetch = fetchMock;

let analyzeMenuFromOriginal: typeof import('../../src/services/ingestion').analyzeMenuFromOriginal;

beforeAll(async () => {
  const mod = await import('../../src/services/ingestion');
  analyzeMenuFromOriginal = mod.analyzeMenuFromOriginal;
});

beforeEach(() => {
  jest.clearAllMocks();
  (fetchMock as jest.Mock).mockRejectedValue(Object.assign(new Error('429'), { status: 429 }));
  (enqueueAgentJobMock as jest.Mock).mockResolvedValue('doc-x');
  (waitForAgentJobMock as jest.Mock).mockResolvedValue({ outputText: '[{"id":"1","name":"Burger"}]' });
});

describe('analyzeOriginalViaVertex fallback', () => {
  it('enqueues agent job and parses outputText', async () => {
    const res = await analyzeMenuFromOriginal(['foo.jpg']);

    expect(fetchMock).toHaveBeenCalled();
    expect(enqueueAgentJobMock).toHaveBeenCalled();
    expect(waitForAgentJobMock).toHaveBeenCalledWith('doc-x', 'analysis');
    expect(res).toEqual([{ id: '1', name: 'Burger', available: true }]);
  });

  it('uses the upload MIME type for Vertex and queued analysis jobs', async () => {
    await analyzeMenuFromOriginal(['foo.png']);

    const fetchBody = JSON.parse(String(fetchMock.mock.calls[0]?.[1]?.body ?? '{}'));
    expect(fetchBody.contents[0].parts[1].fileData.mimeType).toBe('image/png');
    expect(enqueueAgentJobMock).toHaveBeenCalledWith(
      'analysis',
      expect.any(String),
      'gs://test-bucket/foo.png',
      'image/png',
      expect.any(String),
      expect.any(String),
    );
  });
});
