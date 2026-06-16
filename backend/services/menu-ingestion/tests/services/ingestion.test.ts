import { jest } from '@jest/globals';
import { Buffer } from 'node:buffer';
type GenerationModule = typeof import('../../src/services/generation');
type RenderImageFn = GenerationModule['renderImage'];
type GeminiJsonFn = GenerationModule['geminiJson'];

process.env.MENU_BUCKET = 'test-bucket';
process.env.GOOGLE_CLOUD_PROJECT = 'test-project';
process.env.VERTEX_PROJECT = 'test-project';

const saveMock = jest.fn();

jest.mock('@google-cloud/storage', () => ({
  Storage: class Storage {
    bucket() {
      return {
        file: () => ({
          save: saveMock,
          getSignedUrl: async () => ['gs://test-bucket/path'],
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

const renderImageMock = jest.fn() as jest.MockedFunction<RenderImageFn>;
const geminiJsonMock = jest.fn() as jest.MockedFunction<GeminiJsonFn>;

jest.mock('../../src/services/generation', () => ({
  renderImage: (...args: Parameters<RenderImageFn>) => renderImageMock(...args),
  geminiJson: (...args: Parameters<GeminiJsonFn>) => geminiJsonMock(...args),
}));

let generateComposites: typeof import('../../src/services/ingestion').generateComposites;
let extractItemsFromComposites: typeof import('../../src/services/ingestion').extractItemsFromComposites;

beforeAll(async () => {
  const module = await import('../../src/services/ingestion');
  generateComposites = module.generateComposites;
  extractItemsFromComposites = module.extractItemsFromComposites;
});

describe('generation service', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    saveMock.mockReset();
  });

  it('builds composites by calling renderImage and saving to storage', async () => {
    renderImageMock.mockResolvedValue('Zmlu' as any);
    const res = await generateComposites(['foo.jpg'], 'job1');
    expect(res.generatedFiles).toEqual(['menu-generated/job1/page-1.png']);
    expect(renderImageMock).toHaveBeenCalledTimes(1);
    expect(saveMock).toHaveBeenCalled();
    expect(saveMock.mock.calls[0][0]).toBeInstanceOf(Buffer);
  });

  it('throws when no composites are generated (composite required)', async () => {
    renderImageMock.mockResolvedValue(undefined as any);
    await expect(generateComposites(['foo.jpg'], 'job1')).rejects.toThrow('no composites generated');
    expect(renderImageMock).toHaveBeenCalledTimes(1);
    expect(saveMock).not.toHaveBeenCalled();
  });

  it('skips pages whose composites fail and continues with others', async () => {
    renderImageMock
      .mockResolvedValueOnce(undefined as any) // page 1 fails
      .mockResolvedValueOnce('Zmlu' as any); // page 2 succeeds
    const res = await generateComposites(['p1.jpg', 'p2.jpg'], 'job2');
    expect(res.generatedFiles).toEqual(['menu-generated/job2/page-2.png']);
    expect(renderImageMock).toHaveBeenCalledTimes(2);
  });

  it('extracts items and signs URLs', async () => {
    geminiJsonMock.mockResolvedValue({ count: 1 } as any);
    renderImageMock.mockResolvedValue(Buffer.from('a').toString('base64'));
    const res = await extractItemsFromComposites(['gen.png'], 'job1');
    expect(res.images).toHaveLength(1);
    expect(geminiJsonMock).toHaveBeenCalled();
    expect(renderImageMock).toHaveBeenCalledTimes(1);
    expect(saveMock).toHaveBeenCalledTimes(1); // still only one saved for thumbnail
  });
});
