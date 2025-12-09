import request from "supertest";

// Mock external services to avoid network calls
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

describe("/events/orders", () => {
  let app: any;

  beforeEach(async () => {
    process.env.PORT = "8084";
    process.env.ENVIRONMENT = "test";
    process.env.FIREBASE_PROJECT_ID = "demo";
    process.env.FIREBASE_SERVICE_ACCOUNT = JSON.stringify({ project_id: "demo" });
    process.env.NODE_ENV = "test";
    // Import after env setup to allow config validation to pass.
    const mod = await import("../src/index");
    app = mod.app;
  });

  it("rejects missing payload", async () => {
    const res = await request(app).post("/events/orders").send({});
    expect(res.status).toBe(400);
  });

  it("decodes order event and returns 204", async () => {
    const payload = Buffer.from(
      JSON.stringify({
        id: "order-1",
        storeId: "store-1",
        status: "created",
        customerName: "Test",
        totalCents: 1234
      })
    ).toString("base64");

    const res = await request(app)
      .post("/events/orders")
      .send({ message: { data: payload } });

    expect(res.status).toBe(204);
  });
});
