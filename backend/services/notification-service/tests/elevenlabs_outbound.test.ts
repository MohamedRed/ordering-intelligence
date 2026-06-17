import {
  buildElevenLabsOutboundCallRequest,
  startElevenLabsOutboundCall
} from "../src/elevenlabs_outbound";
import type { NotificationConfig, StoreDoc } from "../src/types";

const config: NotificationConfig = {
  PORT: 8080,
  ENVIRONMENT: "test",
  FIREBASE_PROJECT_ID: "demo",
  FIREBASE_SERVICE_ACCOUNT: "{}",
  ELEVENLABS_API_KEY: "el-key",
  ELEVENLABS_API_BASE_URL: "https://api.elevenlabs.io/"
};

const store: StoreDoc = {
  store_id: "store-1",
  elevenlabs_agent_template_id: "agent_123",
  elevenlabs_phone_number_id: "phone_123"
};

const callParams = {
  store,
  toNumber: "+15551234567",
  note: "Pickup is ready.",
  tenantId: "tenant-1",
  storeId: "store-1"
};

describe("ElevenLabs outbound calls", () => {
  let logSpy: jest.SpyInstance;

  beforeEach(() => {
    logSpy = jest.spyOn(console, "log").mockImplementation(() => undefined);
  });

  afterEach(() => {
    logSpy.mockRestore();
  });

  it("builds the outbound-call request from store and tenant context", () => {
    const request = buildElevenLabsOutboundCallRequest(config, callParams);

    expect(request.url).toBe("https://api.elevenlabs.io/v1/convai/twilio/outbound-call");
    expect(request.body).toEqual({
      agent_id: "agent_123",
      agent_phone_number_id: "phone_123",
      to_number: "+15551234567",
      conversation_initiation_client_data: {
        dynamic_variables: {
          tenantId: "tenant-1",
          storeId: "store-1",
          note: "Pickup is ready."
        }
      }
    });
    expect(request.headers).toEqual({
      "xi-api-key": "el-key",
      "Content-Type": "application/json"
    });
  });

  it("starts outbound calls through the configured HTTP client", async () => {
    const post = jest.fn(async () => ({}));

    await expect(
      startElevenLabsOutboundCall({ post }, config, callParams, false)
    ).resolves.toBe("started");

    expect(post).toHaveBeenCalledWith(
      "https://api.elevenlabs.io/v1/convai/twilio/outbound-call",
      expect.objectContaining({ agent_id: "agent_123", to_number: "+15551234567" }),
      expect.objectContaining({
        headers: expect.objectContaining({ "xi-api-key": "el-key" }),
        timeout: 15_000
      })
    );
  });

  it("supports dry-run mode without requiring provider config", async () => {
    const post = jest.fn(async () => ({}));

    await expect(
      startElevenLabsOutboundCall({ post }, { ...config, ELEVENLABS_API_KEY: undefined }, callParams, true)
    ).resolves.toBe("dry_run");

    expect(post).not.toHaveBeenCalled();
  });

  it("fails when provider or store call config is missing", () => {
    expect(() =>
      buildElevenLabsOutboundCallRequest({ ...config, ELEVENLABS_API_KEY: undefined }, callParams)
    ).toThrow("elevenlabs api key not configured for outbound call");

    expect(() =>
      buildElevenLabsOutboundCallRequest(config, {
        ...callParams,
        store: { store_id: "store-1" }
      })
    ).toThrow(
      "elevenlabs store config missing for outbound call: elevenlabs_agent_id or elevenlabs_agent_template_id, elevenlabs_phone_number_id"
    );
  });
});
