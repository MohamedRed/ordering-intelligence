import type express from 'express';

export type OnboardingAuthPolicy = {
  requireAuth: boolean;
  strictEnvironment: boolean;
  firebaseProjectId: string;
  allowGoogleIdTokens: boolean;
  googleIdTokenAudiences: string[];
  googleIdTokenAllowedEmails: string[];
};

type VerifiedIdentity = Record<string, unknown>;

export type OnboardingAuthVerifiers = {
  verifyFirebaseToken: (token: string) => Promise<VerifiedIdentity>;
  verifyGoogleIdToken: (token: string, audiences: string[]) => Promise<VerifiedIdentity>;
};

function csvValues(value?: string): string[] {
  return (value || '')
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function parseBoolean(raw: string | undefined, name: string): boolean | undefined {
  if (raw == null || raw.trim() === '') return undefined;
  const normalized = raw.trim().toLowerCase();
  if (['true', '1', 'yes'].includes(normalized)) return true;
  if (['false', '0', 'no'].includes(normalized)) return false;
  throw new Error(`${name} must be true or false`);
}

function isStrictEnvironment(environment: string): boolean {
  return ['prod', 'production', 'staging'].includes(environment.trim().toLowerCase());
}

export function resolveOnboardingAuthPolicy(
  env: NodeJS.ProcessEnv = process.env,
): OnboardingAuthPolicy {
  const environment = env.ENVIRONMENT || env.NODE_ENV || 'development';
  const strictEnvironment = isStrictEnvironment(environment);
  const explicitRequireAuth = parseBoolean(
    env.ONBOARDING_REQUIRE_AUTH ?? env.REQUIRE_AUTH,
    env.ONBOARDING_REQUIRE_AUTH == null ? 'REQUIRE_AUTH' : 'ONBOARDING_REQUIRE_AUTH',
  );
  const requireAuth = explicitRequireAuth ?? strictEnvironment;

  if (strictEnvironment && explicitRequireAuth === false) {
    throw new Error('Onboarding auth cannot be disabled in staging/production');
  }

  const firebaseProjectId = (env.FIREBASE_PROJECT_ID || env.GOOGLE_CLOUD_PROJECT || '').trim();
  if (requireAuth && !firebaseProjectId) {
    throw new Error('FIREBASE_PROJECT_ID or GOOGLE_CLOUD_PROJECT is required when onboarding auth is enabled');
  }

  const googleIdTokenAudiences = csvValues(
    env.GOOGLE_ID_TOKEN_AUDIENCES ?? env.INTERNAL_AUTH_AUDIENCE,
  );
  const googleIdTokenAllowedEmails = csvValues(
    env.GOOGLE_ID_TOKEN_ALLOWED_EMAILS ?? env.INTERNAL_ALLOWED_EMAILS,
  ).map((email) => email.toLowerCase());
  const allowGoogleIdTokens =
    parseBoolean(env.ALLOW_GOOGLE_ID_TOKENS, 'ALLOW_GOOGLE_ID_TOKENS') ?? false;

  if (requireAuth && allowGoogleIdTokens && !googleIdTokenAudiences.length) {
    throw new Error('GOOGLE_ID_TOKEN_AUDIENCES or INTERNAL_AUTH_AUDIENCE is required when Google ID tokens are enabled');
  }
  if (requireAuth && allowGoogleIdTokens && !googleIdTokenAllowedEmails.length) {
    throw new Error('GOOGLE_ID_TOKEN_ALLOWED_EMAILS or INTERNAL_ALLOWED_EMAILS is required when Google ID tokens are enabled');
  }

  return {
    requireAuth,
    strictEnvironment,
    firebaseProjectId,
    allowGoogleIdTokens,
    googleIdTokenAudiences,
    googleIdTokenAllowedEmails,
  };
}

function isPublicPath(req: express.Request): boolean {
  if (req.method === 'OPTIONS') return true;

  const path = req.path;
  if (path === '/healthz') return true;
  if (path === '/stripe/webhook') return true;

  if (req.method === 'GET' && /^\/stripe\/connect\/[^/]+$/.test(path)) return true;
  if (req.method === 'POST' && /^\/stripe\/connect\/[^/]+\/session$/.test(path)) return true;
  if (req.method === 'GET' && /^\/delivery-partners\/stripe\/connect\/[^/]+$/.test(path)) {
    return true;
  }
  if (req.method === 'POST' && /^\/delivery-partners\/stripe\/connect\/[^/]+\/session$/.test(path)) {
    return true;
  }

  return false;
}

function bearerToken(req: express.Request): string | undefined {
  const header = req.header('Authorization');
  if (!header || !header.toLowerCase().startsWith('bearer ')) return undefined;
  const token = header.slice(7).trim();
  return token || undefined;
}

function googleEmail(identity: VerifiedIdentity): string {
  return String(identity.email || '').trim().toLowerCase();
}

export function createOnboardingAuthMiddleware(
  policy: OnboardingAuthPolicy,
  verifiers: OnboardingAuthVerifiers,
): express.RequestHandler {
  return async (req, res, next) => {
    if (isPublicPath(req)) return next();

    const token = bearerToken(req);
    if (!token) {
      if (!policy.requireAuth) return next();
      return res.status(401).json({ error: 'missing_bearer_token' });
    }

    try {
      const identity = await verifiers.verifyFirebaseToken(token);
      (req as any).user = identity;
      return next();
    } catch (firebaseError) {
      if (!policy.allowGoogleIdTokens) {
        if (!policy.requireAuth) return next();
        console.warn('onboarding firebase auth failed', firebaseError);
        return res.status(401).json({ error: 'invalid_token' });
      }
    }

    try {
      const identity = await verifiers.verifyGoogleIdToken(token, policy.googleIdTokenAudiences);
      const email = googleEmail(identity);
      if (!email || !policy.googleIdTokenAllowedEmails.includes(email)) {
        return res.status(401).json({ error: 'google_identity_not_allowed' });
      }
      (req as any).user = identity;
      return next();
    } catch (googleError) {
      if (!policy.requireAuth) return next();
      console.warn('onboarding google auth failed', googleError);
      return res.status(401).json({ error: 'invalid_token' });
    }
  };
}
