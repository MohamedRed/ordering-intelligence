import { loadConfig } from "../src/config";

describe("config", () => {
  const OLD_ENV = process.env;

  beforeEach(() => {
    process.env = { ...OLD_ENV };
  });

  afterEach(() => {
    process.env = OLD_ENV;
  });

  it("throws when required values are missing", () => {
    delete process.env.ORDER_SERVICE_URL;
    expect(() => loadConfig()).toThrow(/ORDER_SERVICE_URL/);
  });

  it("falls back to defaults", () => {
    process.env.ORDER_SERVICE_URL = "https://orders.example.com";
    const cfg = loadConfig();
    expect(cfg.environment).toBe("dev");
    expect(cfg.port).toBe(8080);
  });

  it("honours overrides", () => {
    process.env.ORDER_SERVICE_URL = "https://orders.example.com";
    process.env.ENVIRONMENT = "test";
    process.env.PORT = "9000";
    const cfg = loadConfig();
    expect(cfg.environment).toBe("test");
    expect(cfg.port).toBe(9000);
  });
});
