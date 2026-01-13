import request from "supertest";

// Reuse mocks to avoid network/Firebase
jest.mock("firebase-admin", () => {
  const messaging = () => ({
    sendEachForMulticast: async () => undefined,
    send: async () => undefined
  });
  const credential = { cert: () => ({}) };
  const initializeApp = () => undefined;
  return {
    __esModule: true,
    default: { messaging, credential, apps: [], initializeApp },
    messaging,
    apps: [] as any[],
    initializeApp,
    credential
  };
});

jest.mock("firebase-admin/app", () => ({
  initializeApp: () => undefined
}));

jest.mock("firebase-admin/auth", () => ({
  getAuth: () => ({ verifyIdToken: async () => ({ uid: "user-1" }) })
}));

jest.mock("@sendgrid/mail", () => ({
  setApiKey: () => undefined,
  send: async () => undefined
}));

jest.mock("twilio", () => () => ({
  messages: { create: async () => undefined }
}));

jest.mock("@google-cloud/firestore", () => {
  return {
    Firestore: class {
      collection() {
        return {
          add: async () => undefined,
          doc: () => ({
            set: async () => undefined
          }),
          get: async () => ({ docs: [] })
        };
      }
    }
  };
});

describe("health and metrics endpoints", () => {
  let app: any;
  beforeEach(async () => {
    process.env.PORT = "8084";
    process.env.ENVIRONMENT = "test";
    process.env.FIREBASE_PROJECT_ID = "demo";
    process.env.FIREBASE_SERVICE_ACCOUNT = JSON.stringify({ project_id: "demo" });
    process.env.NODE_ENV = "test";
    const mod = await import("../src/index");
    app = mod.app;
  });

  it("returns healthz", async () => {
    const res = await request(app).get("/healthz");
    expect(res.status).toBe(200);
    expect(res.body.service).toBe("notification-service");
    expect(res.body.environment).toBe("test");
  });

  it("serves metrics text", async () => {
    const res = await request(app).get("/metrics");
    expect(res.status).toBe(200);
    expect(res.text).toContain("notifications_push_sent_total");
  });
});
