import { loadConfig } from "@ordering-intelligence/config";

describe("notification service config", () => {
  beforeEach(() => {
    process.env.PORT = "9091";
    process.env.ENVIRONMENT = "test";
    process.env.FIREBASE_PROJECT_ID = "demo-project";
    process.env.FIREBASE_SERVICE_ACCOUNT = JSON.stringify({ project_id: "demo-project" });
  });

  it("loads required variables", () => {
    const cfg = loadConfig("notification-service");
    expect(cfg.PORT).toBe(9091);
    expect(cfg.FIREBASE_PROJECT_ID).toBe("demo-project");
  });
});
