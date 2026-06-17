import { NotificationChannels } from "../src/notification_channels";
import type { NotificationConfig, NotifyRequest } from "../src/types";

const config: NotificationConfig = {
  PORT: 8080,
  ENVIRONMENT: "test",
  FIREBASE_PROJECT_ID: "demo",
  FIREBASE_SERVICE_ACCOUNT: "{}",
  OPS_PHONE: "+15550001111",
  OPS_EMAIL: "ops@example.com",
  TWILIO_MESSAGING_NUMBER: "+15550002222",
  SENDGRID_API_KEY: "sendgrid-key",
  SENDGRID_FROM_EMAIL: "alerts@example.com"
};

function makePayload(overrides: Partial<NotifyRequest> = {}): NotifyRequest {
  return {
    channel: ["push"],
    target: { topic: "ops" },
    payload: {
      title: "Test title",
      body: "Test body",
      data: { orderId: "order-1" }
    },
    ...overrides
  };
}

function makeChannels(dryRun = false) {
  return {
    messaging: {
      send: jest.fn(async () => "message-id"),
      sendEachForMulticast: jest.fn(async () => ({ responses: [], successCount: 0, failureCount: 0 }))
    },
    twilioClient: {
      messages: { create: jest.fn(async () => undefined) }
    },
    mailClient: {
      send: jest.fn(async () => undefined)
    },
    instance: undefined as unknown as NotificationChannels
  };
}

describe("NotificationChannels", () => {
  let logSpy: jest.SpyInstance;

  beforeEach(() => {
    logSpy = jest.spyOn(console, "log").mockImplementation(() => undefined);
  });

  afterEach(() => {
    logSpy.mockRestore();
  });

  it("sends push notifications to tokens and topics while tracking metrics", async () => {
    const deps = makeChannels();
    const channels = new NotificationChannels({
      config,
      dryRun: false,
      messaging: deps.messaging,
      twilioClient: deps.twilioClient,
      mailClient: deps.mailClient
    });

    await channels.sendPushNotification(
      makePayload({ target: { deviceTokens: ["token-1", "token-2"], topic: "store-updates" } }),
      "test-source"
    );

    expect(deps.messaging.sendEachForMulticast).toHaveBeenCalledWith(
      expect.objectContaining({
        tokens: ["token-1", "token-2"],
        data: { source: "test-source", orderId: "order-1" }
      })
    );
    expect(deps.messaging.send).toHaveBeenCalledWith(
      expect.objectContaining({
        topic: "store-updates",
        data: { source: "test-source", orderId: "order-1" }
      })
    );
    expect(channels.getCounters().pushSent).toBe(3);
    expect(channels.metricsText()).toContain("notifications_push_sent_total 3");
  });

  it("sends sms and email notifications with configured provider clients", async () => {
    const deps = makeChannels();
    const channels = new NotificationChannels({
      config,
      dryRun: false,
      messaging: deps.messaging,
      twilioClient: deps.twilioClient,
      mailClient: deps.mailClient
    });

    await channels.sendSmsNotification(makePayload({ target: { phoneNumber: "+15551234567" } }));
    await channels.sendEmailNotification(makePayload({ target: { email: "customer@example.com" } }));

    expect(deps.twilioClient.messages.create).toHaveBeenCalledWith({
      to: "+15551234567",
      from: "+15550002222",
      body: "Test body"
    });
    expect(deps.mailClient.send).toHaveBeenCalledWith({
      to: "customer@example.com",
      from: "alerts@example.com",
      subject: "Test title",
      text: "Test body"
    });
    expect(channels.getCounters()).toMatchObject({ smsSent: 1, emailSent: 1 });
  });

  it("supports customer sms and explicit failure counters", async () => {
    const deps = makeChannels();
    const channels = new NotificationChannels({
      config,
      dryRun: false,
      messaging: deps.messaging,
      twilioClient: deps.twilioClient,
      mailClient: deps.mailClient
    });

    await channels.sendCustomerSms({ to: "+15550000001", from: "+15550000002", body: "Ready" });
    channels.recordFailure("push");
    channels.recordFailure("email");

    expect(deps.twilioClient.messages.create).toHaveBeenCalledWith({
      to: "+15550000001",
      from: "+15550000002",
      body: "Ready"
    });
    expect(channels.getCounters()).toMatchObject({ smsSent: 1, pushFailed: 1, emailFailed: 1 });
  });

  it("counts dry-run notifications without calling provider clients", async () => {
    const deps = makeChannels(true);
    const channels = new NotificationChannels({
      config,
      dryRun: true,
      messaging: deps.messaging,
      twilioClient: deps.twilioClient,
      mailClient: deps.mailClient
    });

    await channels.sendPushNotification(makePayload({ target: { topic: "ops" } }), "dry-run");
    await channels.sendSmsNotification(makePayload({ target: { phoneNumber: "+15551234567" } }));
    await channels.sendEmailNotification(makePayload({ target: { email: "customer@example.com" } }));

    expect(deps.messaging.send).not.toHaveBeenCalled();
    expect(deps.twilioClient.messages.create).not.toHaveBeenCalled();
    expect(deps.mailClient.send).not.toHaveBeenCalled();
    expect(channels.metricsText()).toContain("notifications_dry_run 1");
    expect(channels.getCounters()).toMatchObject({ pushSent: 1, smsSent: 1, emailSent: 1 });
  });
});
