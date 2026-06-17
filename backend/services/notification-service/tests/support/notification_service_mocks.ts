export const axiosPost = jest.fn(async () => ({ data: {} }));
jest.mock("axios", () => ({
  __esModule: true,
  default: { post: (...args: any[]) => (axiosPost as any)(...args) }
}));

export const eventCallerEmail = "events-push@demo.iam.gserviceaccount.com";
export const tasksCallerEmail = "tasks-sa@demo.iam.gserviceaccount.com";
const notificationAudience = "https://notification-service.example";

export const oidcVerifyIdToken = jest.fn(async () => ({
  getPayload: () => ({ email: eventCallerEmail })
}));
export const idTokenClientRequest = jest.fn(async () => ({
  data: { phoneE164: "+15551234567", customerName: "Test" }
}));
export const accessTokenClientRequest = jest.fn(async () => ({ data: {} }));

jest.mock("google-auth-library", () => {
  class OAuth2Client {
    verifyIdToken = (options: unknown) => (oidcVerifyIdToken as any)(options);
  }
  class GoogleAuth {
    constructor(_opts?: any) {}
    getIdTokenClient = async (_audience: string) => ({
      request: (...args: any[]) => (idTokenClientRequest as any)(...args)
    });
    getClient = async () => ({
      request: (...args: any[]) => (accessTokenClientRequest as any)(...args)
    });
  }
  return { OAuth2Client, GoogleAuth };
});

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

export const twilioMessagesCreate = jest.fn(async () => undefined);
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

export async function importNotificationApp(callerEmail = eventCallerEmail): Promise<any> {
  jest.resetModules();
  configureNotificationServiceEnv();
  resetNotificationServiceMocks(callerEmail);
  const mod = await import("../../src/index");
  clearFirestoreMocks();
  return mod.app;
}

function configureNotificationServiceEnv(): void {
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
  process.env.ELEVENLABS_API_KEY = "el_key";
  process.env.ELEVENLABS_API_BASE_URL = "https://api.elevenlabs.io";
  process.env.CUSTOMER_PROFILE_SERVICE_URL = "https://customer-profile.example.com";
  process.env.CLOUD_TASKS_PROJECT_ID = "demo";
  process.env.CLOUD_TASKS_LOCATION = "us-central1";
  process.env.CLOUD_TASKS_READY_ESCALATION_QUEUE = "ready-escalation";
  process.env.CLOUD_TASKS_OIDC_SERVICE_ACCOUNT_EMAIL = tasksCallerEmail;
  process.env.NOTIFICATION_SERVICE_URL = "https://notification-service.example";
  process.env.ORDERS_EVENTS_OIDC_AUDIENCE = notificationAudience;
  process.env.DISPATCH_EVENTS_OIDC_AUDIENCE = notificationAudience;
  process.env.DELIVERIES_EVENTS_OIDC_AUDIENCE = notificationAudience;
  process.env.EVENTS_OIDC_ALLOWED_EMAILS = eventCallerEmail;
  process.env.CLOUD_TASKS_OIDC_AUDIENCE = notificationAudience;
  process.env.CLOUD_TASKS_OIDC_ALLOWED_EMAILS = tasksCallerEmail;
  process.env.NODE_ENV = "test";
}

function resetNotificationServiceMocks(callerEmail: string): void {
  twilioMessagesCreate.mockClear();
  axiosPost.mockClear();
  accessTokenClientRequest.mockClear();
  idTokenClientRequest.mockClear();
  oidcVerifyIdToken.mockClear();
  oidcVerifyIdToken.mockResolvedValue({
    getPayload: () => ({ email: callerEmail })
  });
  clearFirestoreMocks();
}

function clearFirestoreMocks(): void {
  (global as any).__firestoreStores?.clear?.();
  (global as any).__firestoreOrders?.clear?.();
  (global as any).__firestoreAlerts?.clear?.();
}
