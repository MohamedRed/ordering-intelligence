import express from 'express';
import request from 'supertest';
import {
  createOnboardingAuthMiddleware,
  resolveOnboardingAuthPolicy,
  type OnboardingAuthPolicy,
  type OnboardingAuthVerifiers,
} from './auth_policy';

function basePolicy(overrides: Partial<OnboardingAuthPolicy> = {}): OnboardingAuthPolicy {
  return {
    requireAuth: true,
    strictEnvironment: true,
    firebaseProjectId: 'test-project',
    allowGoogleIdTokens: true,
    googleIdTokenAudiences: ['https://onboarding.example.com'],
    googleIdTokenAllowedEmails: ['ci@example.iam.gserviceaccount.com'],
    ...overrides,
  };
}

function makeApp(policy: OnboardingAuthPolicy, verifiers: Partial<OnboardingAuthVerifiers> = {}) {
  const app = express();
  app.use(
    createOnboardingAuthMiddleware(policy, {
      verifyFirebaseToken: verifiers.verifyFirebaseToken ?? (async () => ({ uid: 'firebase-user' })),
      verifyGoogleIdToken: verifiers.verifyGoogleIdToken ?? (async () => ({
        email: 'ci@example.iam.gserviceaccount.com',
      })),
    }),
  );
  app.post('/onboarding-sessions', (_req, res) => res.json({ ok: true }));
  app.post('/ingest-pubsub', (_req, res) => res.json({ ok: true }));
  app.get('/healthz', (_req, res) => res.json({ ok: true }));
  app.post('/stripe/webhook', (_req, res) => res.json({ ok: true }));
  app.get('/stripe/connect/test-token', (_req, res) => res.send('ok'));
  app.post('/delivery-partners/stripe/connect/test-token/session', (_req, res) => {
    res.json({ ok: true });
  });
  return app;
}

describe('onboarding auth policy', () => {
  it('requires auth by default in staging and production', () => {
    expect(
      resolveOnboardingAuthPolicy({
        ENVIRONMENT: 'staging',
        FIREBASE_PROJECT_ID: 'test-project',
      } as NodeJS.ProcessEnv),
    ).toMatchObject({ requireAuth: true, strictEnvironment: true });
  });

  it('rejects disabled auth in strict environments', () => {
    expect(() =>
      resolveOnboardingAuthPolicy({
        ENVIRONMENT: 'prod',
        FIREBASE_PROJECT_ID: 'test-project',
        ONBOARDING_REQUIRE_AUTH: 'false',
      } as NodeJS.ProcessEnv),
    ).toThrow(/cannot be disabled/);
  });

  it('requires Firebase project config when auth is enabled', () => {
    expect(() =>
      resolveOnboardingAuthPolicy({
        ENVIRONMENT: 'development',
        ONBOARDING_REQUIRE_AUTH: 'true',
      } as NodeJS.ProcessEnv),
    ).toThrow(/FIREBASE_PROJECT_ID/);
  });

  it('requires Google audiences and allowed emails for strict Google OIDC auth', () => {
    expect(() =>
      resolveOnboardingAuthPolicy({
        ENVIRONMENT: 'prod',
        FIREBASE_PROJECT_ID: 'test-project',
        ALLOW_GOOGLE_ID_TOKENS: 'true',
      } as NodeJS.ProcessEnv),
    ).toThrow(/GOOGLE_ID_TOKEN_AUDIENCES/);

    expect(() =>
      resolveOnboardingAuthPolicy({
        ENVIRONMENT: 'prod',
        FIREBASE_PROJECT_ID: 'test-project',
        ALLOW_GOOGLE_ID_TOKENS: 'true',
        GOOGLE_ID_TOKEN_AUDIENCES: 'https://onboarding.example.com',
      } as NodeJS.ProcessEnv),
    ).toThrow(/GOOGLE_ID_TOKEN_ALLOWED_EMAILS/);
  });

  it('allows local development without auth when not explicitly required', () => {
    expect(
      resolveOnboardingAuthPolicy({
        ENVIRONMENT: 'development',
      } as NodeJS.ProcessEnv),
    ).toMatchObject({ requireAuth: false, strictEnvironment: false });
  });
});

describe('onboarding auth middleware', () => {
  it('rejects protected routes without a bearer token', async () => {
    await request(makeApp(basePolicy())).post('/onboarding-sessions').expect(401, {
      error: 'missing_bearer_token',
    });
  });

  it('accepts Firebase ID tokens on protected routes', async () => {
    const verifyFirebaseToken = jest.fn(async () => ({ uid: 'admin-user' }));
    await request(makeApp(basePolicy(), { verifyFirebaseToken }))
      .post('/onboarding-sessions')
      .set('Authorization', 'Bearer firebase-token')
      .expect(200);
    expect(verifyFirebaseToken).toHaveBeenCalledWith('firebase-token');
  });

  it('accepts allowlisted Google OIDC tokens when Firebase verification fails', async () => {
    const verifyGoogleIdToken = jest.fn(async () => ({
      email: 'ci@example.iam.gserviceaccount.com',
    }));
    await request(
      makeApp(basePolicy(), {
        verifyFirebaseToken: async () => {
          throw new Error('not firebase');
        },
        verifyGoogleIdToken,
      }),
    )
      .post('/ingest-pubsub')
      .set('Authorization', 'Bearer google-token')
      .expect(200);
    expect(verifyGoogleIdToken).toHaveBeenCalledWith('google-token', [
      'https://onboarding.example.com',
    ]);
  });

  it('rejects non-allowlisted Google identities', async () => {
    await request(
      makeApp(basePolicy(), {
        verifyFirebaseToken: async () => {
          throw new Error('not firebase');
        },
        verifyGoogleIdToken: async () => ({ email: 'other@example.com' }),
      }),
    )
      .post('/ingest-pubsub')
      .set('Authorization', 'Bearer google-token')
      .expect(401, { error: 'google_identity_not_allowed' });
  });

  it('leaves explicit public routes unauthenticated', async () => {
    const verifyFirebaseToken = jest.fn(async () => ({ uid: 'admin-user' }));
    const app = makeApp(basePolicy(), { verifyFirebaseToken });

    await request(app).get('/healthz').expect(200);
    await request(app).post('/stripe/webhook').expect(200);
    await request(app).get('/stripe/connect/test-token').expect(200);
    await request(app).post('/delivery-partners/stripe/connect/test-token/session').expect(200);
    expect(verifyFirebaseToken).not.toHaveBeenCalled();
  });
});
