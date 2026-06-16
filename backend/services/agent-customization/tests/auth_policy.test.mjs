import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createAgentCustomizationAuthMiddleware,
  resolveAgentCustomizationAuthPolicy,
} from '../dist/auth_policy.js';

function makeReq({ method = 'GET', path = '/v1/voices', authorization } = {}) {
  return {
    method,
    path,
    header(name) {
      return name.toLowerCase() === 'authorization' ? authorization : undefined;
    },
  };
}

function makeRes() {
  return {
    statusCode: 200,
    body: undefined,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
}

async function runMiddleware(policy, req, verifyFirebaseToken) {
  const res = makeRes();
  let nextCalled = false;
  const middleware = createAgentCustomizationAuthMiddleware(
    policy,
    verifyFirebaseToken ?? (async () => ({ uid: 'user-1' })),
  );
  await middleware(req, res, () => {
    nextCalled = true;
  });
  return { res, nextCalled };
}

test('resolveAgentCustomizationAuthPolicy requires auth in strict environments', () => {
  assert.deepEqual(
    resolveAgentCustomizationAuthPolicy({
      ENVIRONMENT: 'staging',
      FIREBASE_PROJECT_ID: 'test-project',
    }),
    {
      requireAuth: true,
      strictEnvironment: true,
      firebaseProjectId: 'test-project',
    },
  );
});

test('resolveAgentCustomizationAuthPolicy rejects disabled strict auth', () => {
  assert.throws(
    () =>
      resolveAgentCustomizationAuthPolicy({
        ENVIRONMENT: 'prod',
        FIREBASE_PROJECT_ID: 'test-project',
        REQUIRE_AUTH: 'false',
      }),
    /cannot be disabled/,
  );
});

test('resolveAgentCustomizationAuthPolicy requires Firebase project when auth is enabled', () => {
  assert.throws(
    () =>
      resolveAgentCustomizationAuthPolicy({
        ENVIRONMENT: 'development',
        REQUIRE_AUTH: 'true',
      }),
    /FIREBASE_PROJECT_ID/,
  );
});

test('resolveAgentCustomizationAuthPolicy allows unauthenticated local development by default', () => {
  assert.deepEqual(
    resolveAgentCustomizationAuthPolicy({
      ENVIRONMENT: 'development',
    }),
    {
      requireAuth: false,
      strictEnvironment: false,
      firebaseProjectId: '',
    },
  );
});

test('auth middleware rejects protected routes without bearer token', async () => {
  const { res, nextCalled } = await runMiddleware(
    {
      requireAuth: true,
      strictEnvironment: true,
      firebaseProjectId: 'test-project',
    },
    makeReq(),
  );
  assert.equal(nextCalled, false);
  assert.equal(res.statusCode, 401);
  assert.deepEqual(res.body, { error: 'missing_bearer_token' });
});

test('auth middleware accepts valid Firebase bearer token', async () => {
  const calls = [];
  const { res, nextCalled } = await runMiddleware(
    {
      requireAuth: true,
      strictEnvironment: true,
      firebaseProjectId: 'test-project',
    },
    makeReq({ authorization: 'Bearer firebase-token' }),
    async (token) => {
      calls.push(token);
      return { uid: 'user-1' };
    },
  );
  assert.equal(nextCalled, true);
  assert.equal(res.statusCode, 200);
  assert.deepEqual(calls, ['firebase-token']);
});

test('auth middleware rejects invalid Firebase bearer token', async () => {
  const originalWarn = console.warn;
  console.warn = () => {};
  try {
    const { res, nextCalled } = await runMiddleware(
      {
        requireAuth: true,
        strictEnvironment: true,
        firebaseProjectId: 'test-project',
      },
      makeReq({ authorization: 'Bearer invalid-token' }),
      async () => {
        throw new Error('invalid');
      },
    );
    assert.equal(nextCalled, false);
    assert.equal(res.statusCode, 401);
    assert.deepEqual(res.body, { error: 'invalid_token' });
  } finally {
    console.warn = originalWarn;
  }
});

test('auth middleware leaves health and preflight unauthenticated', async () => {
  const policy = {
    requireAuth: true,
    strictEnvironment: true,
    firebaseProjectId: 'test-project',
  };
  const verifyFirebaseToken = async () => {
    throw new Error('should not verify public routes');
  };

  assert.equal((await runMiddleware(policy, makeReq({ path: '/healthz' }), verifyFirebaseToken)).nextCalled, true);
  assert.equal(
    (await runMiddleware(policy, makeReq({ method: 'OPTIONS', path: '/v1/voices' }), verifyFirebaseToken)).nextCalled,
    true,
  );
});
