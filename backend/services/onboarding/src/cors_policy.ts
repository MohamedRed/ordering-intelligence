import type { CorsOptions } from 'cors';

function csvValues(value?: string): string[] {
  return (value || '')
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function isProductionLike(environment: string): boolean {
  return ['prod', 'production', 'staging'].includes(environment.trim().toLowerCase());
}

function normalizeOrigin(origin: string): string {
  if (origin === '*') return origin;

  let parsed: URL;
  try {
    parsed = new URL(origin);
  } catch {
    throw new Error(`Invalid CORS origin "${origin}". Expected an absolute http(s) origin.`);
  }

  if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') {
    throw new Error(`Invalid CORS origin "${origin}". Only http and https origins are supported.`);
  }

  const normalized = parsed.origin;
  const allowedInput = origin.endsWith('/') ? origin.slice(0, -1) : origin;
  if (allowedInput !== normalized) {
    throw new Error(`Invalid CORS origin "${origin}". Include only scheme, host, and optional port.`);
  }

  return normalized;
}

export function resolveCorsOrigins(rawOrigins: string | undefined, environment: string): string[] {
  const origins = csvValues(rawOrigins).map(normalizeOrigin);
  if (!origins.length) {
    throw new Error('CORS_ORIGINS is required for onboarding-service.');
  }

  if (isProductionLike(environment) && origins.includes('*')) {
    throw new Error('Wildcard CORS origins are not allowed for onboarding-service in staging/production.');
  }

  return Array.from(new Set(origins));
}

export function buildCorsOptions(allowedOrigins: readonly string[]): CorsOptions {
  return {
    origin: (origin, callback) => {
      if (!origin || allowedOrigins.includes('*') || allowedOrigins.includes(origin)) {
        callback(null, true);
        return;
      }
      callback(new Error(`CORS blocked for origin: ${origin}`));
    },
  };
}
