import { loadConfig } from "@ordering-intelligence/config";

export interface PaymentsConfig {
  PORT: number;
  ENVIRONMENT: string;
  FIREBASE_PROJECT_ID?: string;
  STRIPE_SECRET_KEY?: string;
  STRIPE_PUBLISHABLE_KEY?: string;
  STRIPE_WEBHOOK_SECRET?: string;
  STRIPE_WEBHOOK_ALLOWED_EVENTS?: string;
  ORDER_SERVICE_URL?: string;
  NOTIFICATION_SERVICE_URL?: string;
  INTERNAL_AUTH_AUDIENCE?: string;
  INTERNAL_ALLOWED_EMAILS?: string;
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
    STRIPE_WEBHOOK_ALLOWED_EVENTS: (process.env.STRIPE_WEBHOOK_ALLOWED_EVENTS || cfg.STRIPE_WEBHOOK_ALLOWED_EVENTS || "").toString(),
    ORDER_SERVICE_URL: (process.env.ORDER_SERVICE_URL || cfg.ORDER_SERVICE_URL || "").toString(),
    NOTIFICATION_SERVICE_URL: (process.env.NOTIFICATION_SERVICE_URL || cfg.NOTIFICATION_SERVICE_URL || "").toString(),
    INTERNAL_AUTH_AUDIENCE: (process.env.INTERNAL_AUTH_AUDIENCE || cfg.INTERNAL_AUTH_AUDIENCE || "").toString(),
    INTERNAL_ALLOWED_EMAILS: (process.env.INTERNAL_ALLOWED_EMAILS || cfg.INTERNAL_ALLOWED_EMAILS || "").toString()
  };
}
