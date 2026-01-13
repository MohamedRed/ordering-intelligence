import "dotenv/config";

import express, { Request, Response } from "express";
import { loadConfig } from "@ordering-intelligence/config";
import { ChannelCommsConfig } from "./config";
import { handleOrdersEvent } from "./orders_events";

const config = loadConfig("channel-comms") as unknown as ChannelCommsConfig;

const app = express();
app.use(express.json());

const port = Number(process.env.PORT || config.PORT || 8091);

app.get("/healthz", (_req: Request, res: Response) => {
  res.json({ status: "ok", service: "channel-comms", environment: config.ENVIRONMENT });
});

app.post("/events/orders", async (req: Request, res: Response) => {
  await handleOrdersEvent(req, res, config);
});

app.listen(port, () => {
  console.log(`channel-comms listening on ${port}`);
});
