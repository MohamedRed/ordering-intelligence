import { loadConfig } from "@ordering-intelligence/config";

export interface PaymentsConfig {
  PORT: number;
  ENVIRONMENT: string;
  FIREBASE_PROJECT_ID?: string;
  STRIPE_SECRET_KEY?: string;
  STRIPE_PUBLISHABLE_KEY?: string;
  STRIPE_WEBHOOK_SECRET?: string;
  ORDER_SERVICE_URL?: string;
  NOTIFICATION_SERVICE_URL?: string;
}

export function getConfig(): PaymentsConfig {
  const cfg = loadConfig("payments-service") as unknown as Record<string, string>;
  const port = Number(process.env.PORT || cfg.PORT || 8095);
  return {
    PORT: Number.isNaN(port) ? 8095 : port,
    ENVIRONMENT: (process.env.ENVIRONMENT || cfg.ENVIRONMENT || "development").toString(),
    FIREBASE_PROJECT_ID: (process.env.FIREBASE_PROJECT_ID || cfg.FIREBASE_PROJECT_ID || "").toString(),
    STRIPE_SECRET_KEY: (process.env.STRIPE_SECRET_KEY || "").toString(),
    STRIPE_PUBLISHABLE_KEY: (process.env.STRIPE_PUBLISHABLE_KEY || cfg.STRIPE_PUBLISHABLE_KEY || "").toString(),
    STRIPE_WEBHOOK_SECRET: (process.env.STRIPE_WEBHOOK_SECRET || "").toString(),
    ORDER_SERVICE_URL: (process.env.ORDER_SERVICE_URL || cfg.ORDER_SERVICE_URL || "").toString(),
    NOTIFICATION_SERVICE_URL: (process.env.NOTIFICATION_SERVICE_URL || cfg.NOTIFICATION_SERVICE_URL || "").toString()
  };
}
