import type express from 'express';

export type AgentCustomizationAuthPolicy = {
  requireAuth: boolean;
  strictEnvironment: boolean;
  firebaseProjectId: string;
};

export type VerifiedFirebaseIdentity = Record<string, unknown>;

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

export function resolveAgentCustomizationAuthPolicy(
  env: NodeJS.ProcessEnv = process.env,
): AgentCustomizationAuthPolicy {
  const environment = env.ENVIRONMENT || env.NODE_ENV || 'development';
  const strictEnvironment = isStrictEnvironment(environment);
  const explicitRequireAuth = parseBoolean(env.REQUIRE_AUTH, 'REQUIRE_AUTH');
  const requireAuth = explicitRequireAuth ?? strictEnvironment;

  if (strictEnvironment && explicitRequireAuth === false) {
    throw new Error('Agent customization auth cannot be disabled in staging/production');
  }

  const firebaseProjectId = (env.FIREBASE_PROJECT_ID || env.GOOGLE_CLOUD_PROJECT || '').trim();
  if (requireAuth && !firebaseProjectId) {
    throw new Error('FIREBASE_PROJECT_ID or GOOGLE_CLOUD_PROJECT is required when agent customization auth is enabled');
  }

  return {
    requireAuth,
    strictEnvironment,
    firebaseProjectId,
  };
}

function isPublicPath(req: express.Request): boolean {
  return req.method === 'OPTIONS' || req.path === '/healthz';
}

function bearerToken(req: express.Request): string | undefined {
  const header = req.header('Authorization');
  if (!header || !header.toLowerCase().startsWith('bearer ')) return undefined;
  const token = header.slice(7).trim();
  return token || undefined;
}

export function createAgentCustomizationAuthMiddleware(
  policy: AgentCustomizationAuthPolicy,
  verifyFirebaseToken: (token: string) => Promise<VerifiedFirebaseIdentity>,
): express.RequestHandler {
  return async (req, res, next) => {
    if (isPublicPath(req)) return next();

    const token = bearerToken(req);
    if (!token) {
      if (!policy.requireAuth) return next();
      return res.status(401).json({ error: 'missing_bearer_token' });
    }

    try {
      const identity = await verifyFirebaseToken(token);
      (req as any).user = identity;
      return next();
    } catch (error) {
      if (!policy.requireAuth) return next();
      console.warn('agent-customization auth failed', error);
      return res.status(401).json({ error: 'invalid_token' });
    }
  };
}
