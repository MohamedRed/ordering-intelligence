import express, { Request, Response } from "express";
import { loadConfig, ServiceConfig } from "./config";

export function createApp(config: ServiceConfig) {
  const app = express();
  app.use(express.json());
  app.set("port", config.port);

  app.get("/healthz", (_req: Request, res: Response) => {
    res.json({ status: "ok", service: "pos-export", environment: config.environment });
  });

  app.get("/exports/orders", async (req: Request, res: Response) => {
    const storeId = req.query.storeId as string | undefined;
    if (!storeId) {
      res.status(400).json({ error: "missing_store_id" });
      return;
    }

    try {
      const response = await fetch(`${config.orderServiceUrl}/exports/orders?storeId=${encodeURIComponent(storeId)}`);
      if (!response.ok) {
        throw new Error(`order service responded with ${response.status}`);
      }
      const payload = await response.json();
      res.setHeader("content-type", "text/csv");
      res.setHeader("x-pos-export-source", "order-service");
      res.send(payload.csv ?? "");
    } catch (error) {
      console.error("failed to proxy order export", error);
      res.status(502).json({ error: "export_failed" });
    }
  });

  return app;
}

export function createServer() {
  const config = loadConfig();
  const app = createApp(config);
  app.listen(config.port, () => {
    console.log(`pos-export service listening on :${config.port}`);
  });
  return app;
}

if (require.main === module) {
  createServer();
}
