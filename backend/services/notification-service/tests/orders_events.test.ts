import request from "supertest";

const axiosPost = jest.fn(async () => ({ data: {} }));
jest.mock("axios", () => ({
  __esModule: true,
  default: { post: (...args: any[]) => (axiosPost as any)(...args) }
}));

const eventCallerEmail = "events-push@demo.iam.gserviceaccount.com";
const tasksCallerEmail = "tasks-sa@demo.iam.gserviceaccount.com";
const notificationAudience = "https://notification-service.example";
const oidcVerifyIdToken = jest.fn(async () => ({
  getPayload: () => ({ email: eventCallerEmail })
}));
const idTokenClientRequest = jest.fn(async () => ({ data: { phoneE164: "+15551234567", customerName: "Test" } }));
const accessTokenClientRequest = jest.fn(async () => ({ data: {} }));
jest.mock("google-auth-library", () => {
  class OAuth2Client {
    verifyIdToken = (options: unknown) => (oidcVerifyIdToken as any)(options);
  }
  class GoogleAuth {
    constructor(_opts?: any) {}
    getIdTokenClient = async (_audience: string) => ({ request: (...args: any[]) => (idTokenClientRequest as any)(...args) });
    getClient = async () => ({ request: (...args: any[]) => (accessTokenClientRequest as any)(...args) });
  }
  return { OAuth2Client, GoogleAuth };
});

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

const twilioMessagesCreate = jest.fn(async () => undefined);
jest.mock("twilio", () => () => ({
  messages: { create: (...args: any[]) => (twilioMessagesCreate as any)(...args) }
}));

jest.mock("@google-cloud/firestore", () => {
  const stores = new Map<string, any>();
  const orders = new Map<string, any>();
  const alerts = new Map<string, any>();

  const docSnapshot = (data: any) => ({
    exists: data !== undefined,
    data: () => data
  });

  const setDoc = async (col: string, id: string, data: any) => {
    if (col === "stores") stores.set(id, data);
    if (col === "orders") orders.set(id, data);
    if (col === "alerts") alerts.set(id, data);
  };

  const getDoc = (col: string, id: string) => {
    if (col === "stores") return stores.get(id);
    if (col === "orders") return orders.get(id);
    if (col === "alerts") return alerts.get(id);
    return undefined;
  };

  // Expose helpers for test setup via global.
  (global as any).__firestoreStores = stores;
  (global as any).__firestoreOrders = orders;
  (global as any).__firestoreAlerts = alerts;

  return {
    Firestore: class {
      collection(name: string) {
        return {
          doc: (id: string) => ({
            set: async (data: any) => setDoc(name, id, data),
            get: async () => docSnapshot(getDoc(name, id))
          }),
          orderBy: () => ({
            limit: () => ({
              get: async () => ({ docs: [] })
            })
          }),
          limit: () => ({
            get: async () => ({ docs: [] })
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
    jest.resetModules();
    process.env.PORT = "8084";
    process.env.ENVIRONMENT = "test";
    process.env.FIREBASE_PROJECT_ID = "demo";
    process.env.FIREBASE_SERVICE_ACCOUNT = JSON.stringify({ project_id: "demo" });
    process.env.TWILIO_ACCOUNT_SID = "ACxxx";
    process.env.TWILIO_AUTH_TOKEN = "tok";
    process.env.TWILIO_MESSAGING_NUMBER = "+15550000000";
    process.env.SENDGRID_API_KEY = "sg_key";
    process.env.OPS_PHONE = "+15550009999";
    process.env.OPS_EMAIL = "ops@example.com";
    process.env.CLOUD_TASKS_PROJECT_ID = "demo";
    process.env.CLOUD_TASKS_LOCATION = "us-central1";
    process.env.CLOUD_TASKS_READY_ESCALATION_QUEUE = "ready-escalation";
    process.env.CLOUD_TASKS_OIDC_SERVICE_ACCOUNT_EMAIL = "tasks-sa@demo.iam.gserviceaccount.com";
    process.env.NOTIFICATION_SERVICE_URL = "https://notification-service.example";
    process.env.ORDERS_EVENTS_OIDC_AUDIENCE = notificationAudience;
    process.env.DISPATCH_EVENTS_OIDC_AUDIENCE = notificationAudience;
    process.env.DELIVERIES_EVENTS_OIDC_AUDIENCE = notificationAudience;
    process.env.EVENTS_OIDC_ALLOWED_EMAILS = eventCallerEmail;
    process.env.CLOUD_TASKS_OIDC_AUDIENCE = notificationAudience;
    process.env.CLOUD_TASKS_OIDC_ALLOWED_EMAILS = tasksCallerEmail;
    process.env.NODE_ENV = "test";
    // Import after env setup to allow config validation to pass.
    const mod = await import("../src/index");
    app = mod.app;

    twilioMessagesCreate.mockClear();
    axiosPost.mockClear();
    accessTokenClientRequest.mockClear();
    idTokenClientRequest.mockClear();
    oidcVerifyIdToken.mockClear();
    oidcVerifyIdToken.mockResolvedValue({
      getPayload: () => ({ email: eventCallerEmail })
    });

    (global as any).__firestoreStores?.clear?.();
    (global as any).__firestoreOrders?.clear?.();
    (global as any).__firestoreAlerts?.clear?.();
  });

  it("rejects missing payload", async () => {
    const res = await request(app)
      .post("/events/orders")
      .set("Authorization", "Bearer event-token")
      .send({});
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
      .set("Authorization", "Bearer event-token")
      .send({ message: { data: payload } });

    expect(res.status).toBe(204);
  });

  it("sends customer SMS based on store defaults when statusChange is present", async () => {
    (global as any).__firestoreStores.set("store-1", {
      store_id: "store-1",
      twilio_number: "+15550001111",
      order_comms: {
        statuses: {
          ready: { default_channel: "sms" }
        }
      }
    });

    const payload = Buffer.from(
      JSON.stringify({
        id: "order-2",
        storeId: "store-1",
        status: "ready",
        tenantId: "tenant-1",
        callerId: "+15551230000",
        statusChange: {
          previousStatus: "confirmed",
          newStatus: "ready",
          notifyMode: "auto",
          note: "Your order is ready for pickup."
        }
      })
    ).toString("base64");

    const res = await request(app)
      .post("/events/orders")
      .set("Authorization", "Bearer event-token")
      .send({ message: { data: payload } });

    expect(res.status).toBe(204);
    expect(twilioMessagesCreate).toHaveBeenCalledWith(
      expect.objectContaining({
        to: "+15551230000",
        from: "+15550001111",
        body: "Your order is ready for pickup."
      })
    );
  });

  it("enqueues ready escalation task when enabled", async () => {
    (global as any).__firestoreStores.set("store-1", {
      store_id: "store-1",
      twilio_number: "+15550001111",
      order_comms: {
        ready_escalation_enabled: true,
        ready_escalation_minutes: 1,
        statuses: {
          ready: { default_channel: "none" }
        }
      }
    });

    const payload = Buffer.from(
      JSON.stringify({
        id: "order-3",
        storeId: "store-1",
        status: "ready",
        tenantId: "tenant-1",
        callerId: "+15551230000",
        statusChange: {
          previousStatus: "confirmed",
          newStatus: "ready",
          notifyMode: "none"
        }
      })
    ).toString("base64");

    const res = await request(app)
      .post("/events/orders")
      .set("Authorization", "Bearer event-token")
      .send({ message: { data: payload } });

    expect(res.status).toBe(204);
    expect(accessTokenClientRequest).toHaveBeenCalled();
    const call = (accessTokenClientRequest as any).mock.calls[0]?.[0];
    expect(call).toBeTruthy();
    expect(String(call.url)).toContain("cloudtasks.googleapis.com");
    expect(call.data.task.httpRequest.url).toBe("https://notification-service.example/tasks/ready-escalation");
  });
});

describe("/tasks/ready-escalation", () => {
  let app: any;

  beforeEach(async () => {
    jest.resetModules();
    process.env.PORT = "8084";
    process.env.ENVIRONMENT = "test";
    process.env.FIREBASE_PROJECT_ID = "demo";
    process.env.FIREBASE_SERVICE_ACCOUNT = JSON.stringify({ project_id: "demo" });
    process.env.TWILIO_ACCOUNT_SID = "ACxxx";
    process.env.TWILIO_AUTH_TOKEN = "tok";
    process.env.TWILIO_MESSAGING_NUMBER = "+15550000000";
    process.env.ELEVENLABS_API_KEY = "el_key";
    process.env.ELEVENLABS_API_BASE_URL = "https://api.elevenlabs.io";
    process.env.CLOUD_TASKS_OIDC_AUDIENCE = notificationAudience;
    process.env.CLOUD_TASKS_OIDC_ALLOWED_EMAILS = tasksCallerEmail;
    process.env.NODE_ENV = "test";
    const mod = await import("../src/index");
    app = mod.app;

    twilioMessagesCreate.mockClear();
    axiosPost.mockClear();
    accessTokenClientRequest.mockClear();
    idTokenClientRequest.mockClear();
    oidcVerifyIdToken.mockClear();
    oidcVerifyIdToken.mockResolvedValue({
      getPayload: () => ({ email: tasksCallerEmail })
    });
    (global as any).__firestoreStores?.clear?.();
    (global as any).__firestoreOrders?.clear?.();
    (global as any).__firestoreAlerts?.clear?.();
  });

  it("starts outbound call when order still ready and store escalation enabled", async () => {
    (global as any).__firestoreOrders.set("order-4", {
      id: "order-4",
      storeId: "store-1",
      status: "ready",
      tenantId: "tenant-1",
      callerId: "+15551230000"
    });
    (global as any).__firestoreStores.set("store-1", {
      store_id: "store-1",
      elevenlabs_agent_template_id: "agent_123",
      elevenlabs_phone_number_id: "pn_123",
      order_comms: {
        ready_escalation_enabled: true,
        ready_escalation_channel: "call"
      }
    });

    const res = await request(app)
      .post("/tasks/ready-escalation")
      .set("Authorization", "Bearer task-token")
      .send({ orderId: "order-4", storeId: "store-1" });

    expect(res.status).toBe(204);
    expect(axiosPost).toHaveBeenCalledWith(
      "https://api.elevenlabs.io/v1/convai/twilio/outbound-call",
      expect.objectContaining({
        agent_id: "agent_123",
        agent_phone_number_id: "pn_123",
        to_number: "+15551230000"
      }),
      expect.any(Object)
    );
  });
});
