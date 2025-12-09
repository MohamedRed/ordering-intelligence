import request from "supertest";
import { createApp } from "../src/index";
import { ServiceConfig } from "../src/config";

describe("GET /exports/orders", () => {
  const originalEnv = process.env;
  const fetchMock = jest.fn();
  const baseConfig: ServiceConfig = {
    environment: "test",
    port: 0,
    orderServiceUrl: "https://orders.example.com"
  };

  beforeEach(() => {
    fetchMock.mockReset();
    global.fetch = fetchMock as unknown as typeof fetch;
  });

  afterAll(() => {
    process.env = originalEnv;
    // @ts-ignore
    global.fetch = undefined;
  });

  it("requires storeId", async () => {
    const app = createApp(baseConfig);
    const response = await request(app).get("/exports/orders");
    expect(response.status).toBe(400);
  });

  it("returns csv from upstream", async () => {
    const app = createApp(baseConfig);
    const csv = "order_id,total\n1,10.00";
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({ csv })
    });

    const response = await request(app).get("/exports/orders?storeId=abc");
    expect(fetchMock).toHaveBeenCalledWith("https://orders.example.com/exports/orders?storeId=abc");
    expect(response.status).toBe(200);
    expect(response.text).toBe(csv);
    expect(response.headers["content-type"]).toContain("text/csv");
  });

  it("handles upstream failure", async () => {
    const app = createApp(baseConfig);
    fetchMock.mockResolvedValue({
      ok: false,
      status: 502
    });

    const response = await request(app).get("/exports/orders?storeId=abc");
    expect(response.status).toBe(502);
    expect(response.body.error).toBe("export_failed");
  });
});
