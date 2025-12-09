import { jest } from '@jest/globals';

process.env.MENU_BUCKET = 'test-bucket';
process.env.MENU_INGEST_TOPIC = 'test-topic';
process.env.GOOGLE_CLOUD_PROJECT = 'test-project';
process.env.VERTEX_PROJECT = 'test-project';

const ctorOpts: any[] = [];

class Firestore {
  constructor(opts?: any) {
    ctorOpts.push(opts);
  }
}

jest.mock('@google-cloud/firestore', () => ({
  Firestore,
}));

// Mock Storage/PubSub to avoid real calls during app import
jest.mock('@google-cloud/storage', () => ({
  Storage: class Storage {
    bucket() {
      return { file: () => ({ getSignedUrl: async () => ['http://example'] }) };
    }
  },
}));
jest.mock('@google-cloud/pubsub', () => ({
  PubSub: class PubSub {
    topic() {
      return { publishMessage: async () => undefined };
    }
  },
}));
jest.mock('firebase-admin/app', () => ({
  initializeApp: () => undefined,
  applicationDefault: () => ({}),
}));
jest.mock('firebase-admin/auth', () => ({
  getAuth: () => ({ verifyIdToken: async () => ({ uid: 'test' }) }),
}));

describe('Firestore client options', () => {
  beforeAll(async () => {
    // Import modules that construct Firestore instances.
    await import('../../src/app');
    await import('../../src/services/ingestion');
    await import('../../src/services/agent_queue');
  });

  it('sets ignoreUndefinedProperties on all Firestore clients', () => {
    expect(ctorOpts.length).toBeGreaterThanOrEqual(3);
    for (const opts of ctorOpts) {
      expect(opts?.ignoreUndefinedProperties).toBe(true);
    }
  });
});
