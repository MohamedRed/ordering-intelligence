import express, { Request, Response } from "express";
import request from "supertest";

import { loadConfig } from "@ordering-intelligence/config";

describe("handoff endpoint", () => {
  beforeEach(() => {
    process.env.PORT = "8084";
    process.env.ENVIRONMENT = "test";
    process.env.FIREBASE_PROJECT_ID = "demo";
    process.env.FIREBASE_SERVICE_ACCOUNT = JSON.stringify({ project_id: "demo" });
  });

  it("returns 400 when missing callSid", async () => {
    const config = loadConfig("notification-service");
    const app = express();
    app.use(express.json());
    app.post("/handoff", (req: Request, res: Response) => {
      const { callSid } = req.body ?? {};
      if (!callSid) {
        res.status(400).json({ error: "missing_callSid" });
        return;
      }
      res.status(202).json({ status: "queued" });
    });

    const response = await request(app).post("/handoff").send({});
    expect(response.status).toBe(400);
    expect(config.ENVIRONMENT).toBe("test");
  });
});
