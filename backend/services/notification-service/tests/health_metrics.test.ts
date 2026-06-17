import request from "supertest";

const verifyIdTokenMock = jest.fn(async (_options: unknown) => ({
  getPayload: () => ({ email: "metrics@example.iam.gserviceaccount.com" })
}));

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

jest.mock("google-auth-library", () => ({
  GoogleAuth: class {
    constructor() {}
  },
  OAuth2Client: class {
    verifyIdToken = (options: unknown) => verifyIdTokenMock(options);
  }
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
    jest.resetModules();
    verifyIdTokenMock.mockClear();
    process.env.PORT = "8084";
    process.env.ENVIRONMENT = "test";
    process.env.FIREBASE_PROJECT_ID = "demo";
    process.env.FIREBASE_SERVICE_ACCOUNT = JSON.stringify({ project_id: "demo" });
    process.env.INTERNAL_AUTH_AUDIENCE = "https://notification-service.example";
    process.env.INTERNAL_ALLOWED_EMAILS = "metrics@example.iam.gserviceaccount.com";
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

  it("requires internal auth for metrics", async () => {
    const res = await request(app).get("/metrics");
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "missing_auth" });
  });

  it("serves metrics text to allowlisted internal callers", async () => {
    const res = await request(app).get("/metrics").set("Authorization", "Bearer metrics-token");
    expect(res.status).toBe(200);
    expect(res.text).toContain("notifications_push_sent_total");
    expect(verifyIdTokenMock).toHaveBeenCalledWith({
      idToken: "metrics-token",
      audience: "https://notification-service.example"
    });
  });
});
