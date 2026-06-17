import express, { Request, Response } from "express";
import { ChannelCommsConfig } from "./config";
import { handleOrdersEvent } from "./orders_events";

export function createChannelCommsApp(config: ChannelCommsConfig) {
  const app = express();
  app.use(express.json({ limit: "1mb" }));

  app.get("/healthz", (_req: Request, res: Response) => {
    res.json({ status: "ok", service: "channel-comms", environment: config.ENVIRONMENT });
  });

  app.post("/events/orders", async (req: Request, res: Response) => {
    await handleOrdersEvent(req, res, config);
  });

  return app;
}
