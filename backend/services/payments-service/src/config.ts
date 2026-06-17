import { loadConfig } from "@ordering-intelligence/config";

export interface PaymentsConfig {
  PORT: number;
  ENVIRONMENT: string;
  CORS_ORIGINS: string[];
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

function parseCsv(value?: string): string[] {
  return (value || "")
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
}

export function isProductionLike(environment: string): boolean {
  return ["prod", "production", "staging"].includes(environment.trim().toLowerCase());
}

function normalizeCorsOrigin(origin: string): string {
  if (origin === "*") return origin;

  let parsed: URL;
  try {
    parsed = new URL(origin);
  } catch {
    throw new Error(`Invalid CORS origin "${origin}". Expected an absolute http(s) origin.`);
  }

  if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
    throw new Error(`Invalid CORS origin "${origin}". Only http and https origins are supported.`);
  }

  const normalized = parsed.origin;
  const allowedInput = origin.endsWith("/") ? origin.slice(0, -1) : origin;
  if (allowedInput !== normalized) {
    throw new Error(`Invalid CORS origin "${origin}". Include only scheme, host, and optional port.`);
  }

  return normalized;
}

export function resolveCorsOrigins(rawOrigins: string | undefined, environment: string): string[] {
  const origins = parseCsv(rawOrigins).map(normalizeCorsOrigin);
  if (!origins.length) {
    throw new Error("CORS_ORIGINS is required for payments-service.");
  }

  if (isProductionLike(environment) && origins.includes("*")) {
    throw new Error("Wildcard CORS origins are not allowed for payments-service in staging/production.");
  }

  return Array.from(new Set(origins));
}

export function getConfig(): PaymentsConfig {
  const cfg = loadConfig("payments-service") as unknown as Record<string, string>;
  const port = Number(process.env.PORT || cfg.PORT || 8095);
  const environment = (process.env.ENVIRONMENT || cfg.ENVIRONMENT || "development").toString();
  const corsOrigins = (process.env.CORS_ORIGINS || cfg.CORS_ORIGINS || "").toString();
  const internalAuthAudience = (process.env.INTERNAL_AUTH_AUDIENCE || cfg.INTERNAL_AUTH_AUDIENCE || "").toString();
  const internalAllowedEmails = (process.env.INTERNAL_ALLOWED_EMAILS || cfg.INTERNAL_ALLOWED_EMAILS || "").toString();
  if (isProductionLike(environment)) {
    if (!internalAuthAudience.trim() || parseCsv(internalAllowedEmails).length === 0) {
      throw new Error(
        "INTERNAL_AUTH_AUDIENCE and INTERNAL_ALLOWED_EMAILS are required for payments-service in staging/production."
      );
    }
  }

  return {
    PORT: Number.isNaN(port) ? 8095 : port,
    ENVIRONMENT: environment,
    CORS_ORIGINS: resolveCorsOrigins(corsOrigins, environment),
    FIREBASE_PROJECT_ID: (process.env.FIREBASE_PROJECT_ID || cfg.FIREBASE_PROJECT_ID || "").toString(),
    STRIPE_SECRET_KEY: (process.env.STRIPE_SECRET_KEY || "").toString(),
    STRIPE_PUBLISHABLE_KEY: (process.env.STRIPE_PUBLISHABLE_KEY || cfg.STRIPE_PUBLISHABLE_KEY || "").toString(),
    STRIPE_WEBHOOK_SECRET: (process.env.STRIPE_WEBHOOK_SECRET || "").toString(),
    STRIPE_WEBHOOK_ALLOWED_EVENTS: (process.env.STRIPE_WEBHOOK_ALLOWED_EVENTS || cfg.STRIPE_WEBHOOK_ALLOWED_EVENTS || "").toString(),
    ORDER_SERVICE_URL: (process.env.ORDER_SERVICE_URL || cfg.ORDER_SERVICE_URL || "").toString(),
    NOTIFICATION_SERVICE_URL: (process.env.NOTIFICATION_SERVICE_URL || cfg.NOTIFICATION_SERVICE_URL || "").toString(),
    INTERNAL_AUTH_AUDIENCE: internalAuthAudience,
    INTERNAL_ALLOWED_EMAILS: internalAllowedEmails
  };
}
