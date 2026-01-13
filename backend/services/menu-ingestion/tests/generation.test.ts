import { renderImage } from '../src/services/generation';

jest.mock('google-auth-library', () => ({
  GoogleAuth: jest.fn().mockImplementation(() => ({
    getAccessToken: jest.fn(async () => 'token'),
  })),
}));

jest.mock('@google-cloud/storage', () => ({
  Storage: class {
    bucket() {
      return {
        file: () => ({
          getSignedUrl: async () => ['https://signed-url'],
        }),
      };
    }
  },
}));

jest.mock('@google-cloud/vertexai', () => ({
  VertexAI: class {
    getGenerativeModel() {
      return {
        generateContent: async () => ({ response: {} }),
      };
    }
  },
}));

jest.mock('../src/services/agent_queue', () => ({
  enqueueAgentJob: jest.fn(async () => 'job-1'),
  waitForAgentJob: jest.fn(async () => ({ outputB64: 'YWdlbnQ=' })),
}));

jest.mock('../src/utils.js', () => ({
  delay: jest.fn(async () => {}),
  parseGsUri: jest.requireActual('../src/utils').parseGsUri,
}));

jest.mock('../src/config.js', () => ({
  VERTEX_PROJECT: 'proj',
  IMAGE_REGION: 'us-central1',
  COMPOSITE_MODEL: 'model',
  RENDER_MODEL: 'model',
  GEN_TIMEOUT_MS: 5000,
  RENDER_TIMEOUT_MS: 2000,
  RENDER_RETRIES: 1,
  RENDER_BASE_DELAY_MS: 1,
  RENDER_MIN_INTERVAL_MS: 0,
  AGENT_COMPOSITE_URL: '',
  AGENT_ANALYSIS_URL: '',
  AGENT_RETRIES: 1,
  AGENT_BASE_DELAY_MS: 1,
}));

const fetchMock = jest.fn();

describe('renderImage', () => {
  beforeEach(() => {
    fetchMock.mockReset();
    (global as any).fetch = fetchMock;
  });

  it('throws when fileUri missing', async () => {
    await expect(
      renderImage({ prompt: 'p', mimeType: 'image/png', modelId: 'm', label: 'label', fileUri: '' })
    ).rejects.toThrow('label requires fileUri input');
  });

  it('returns base64 when generation succeeds', async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      status: 200,
      text: async () =>
        JSON.stringify({
          candidates: [
            {
              content: {
                parts: [{ inlineData: { data: 'YmFzZTY0' } }],
              },
            },
          ],
        }),
    });

    const res = await renderImage({
      prompt: 'p',
      mimeType: 'image/png',
      modelId: 'm',
      label: 'label',
      fileUri: 'gs://bucket/input.png',
    });

    expect(res).toBe('YmFzZTY0');
    expect(fetchMock).toHaveBeenCalled();
  });

  it('falls back to agent outputB64 on error', async () => {
    fetchMock.mockResolvedValue({
      ok: false,
      status: 500,
      statusText: 'err',
      text: async () => 'oops',
    });

    const res = await renderImage({
      prompt: 'p',
      mimeType: 'image/png',
      modelId: 'm',
      label: 'label',
      fileUri: 'gs://bucket/input.png',
    });

    expect(res).toBe('YWdlbnQ=');
  });
});
