import type { CorsOptions } from "cors";

export const DEFAULT_NOTIFICATION_CORS_ORIGINS = [
  "http://localhost:3000",
  "http://localhost:4000",
  "http://localhost:4001",
  "http://127.0.0.1:4000"
];

function parseCsv(value?: string): string[] {
  return String(value || "")
    .split(",")
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function isProductionLike(environment: string): boolean {
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

export function resolveNotificationCorsOrigins(rawOrigins: string | undefined, environment: string): string[] {
  const origins = parseCsv(rawOrigins).map(normalizeCorsOrigin);
  const strict = isProductionLike(environment);
  if (!origins.length) {
    if (strict) {
      throw new Error("CORS_ORIGINS is required for notification-service in staging/production.");
    }
    return DEFAULT_NOTIFICATION_CORS_ORIGINS;
  }

  if (strict && origins.includes("*")) {
    throw new Error("Wildcard CORS origins are not allowed for notification-service in staging/production.");
  }

  return Array.from(new Set(origins));
}

export function buildNotificationCorsOptions(allowedOrigins: readonly string[]): CorsOptions {
  const allowAnyOrigin = allowedOrigins.includes("*");
  const allowed = new Set(allowedOrigins);
  return {
    origin: (origin, callback) => {
      if (!origin || allowAnyOrigin || allowed.has(origin)) {
        callback(null, true);
        return;
      }
      callback(new Error(`CORS blocked for origin: ${origin}`));
    },
    methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Authorization"],
    maxAge: 300
  };
}
