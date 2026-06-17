const assert = require("node:assert/strict");
const test = require("node:test");

const {
  isPublicPaymentsPath,
  parseAllowedEmails,
  requireInternalAuth,
  requirePaymentsInternalAuth
} = require("../dist/internal_auth");

const configuredAuth = {
  INTERNAL_AUTH_AUDIENCE: "https://payments.example.com",
  INTERNAL_ALLOWED_EMAILS: "payments-caller@example.iam.gserviceaccount.com"
};

function makeRequest({ method = "POST", path = "/orders/order-1/refund", headers = {} } = {}) {
  return {
    method,
    path,
    header(name) {
      return headers[name] ?? headers[name.toLowerCase()] ?? "";
    }
  };
}

function makeResponse() {
  return {
    statusCode: undefined,
    body: undefined,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    }
  };
}

test("parseAllowedEmails trims empty entries", () => {
  assert.deepEqual(
    parseAllowedEmails(" caller@example.com, ,Other@example.com "),
    ["caller@example.com", "Other@example.com"]
  );
});

test("isPublicPaymentsPath only exposes health and signed Stripe webhook", () => {
  assert.equal(isPublicPaymentsPath("/healthz"), true);
  assert.equal(isPublicPaymentsPath("/healthz/"), true);
  assert.equal(isPublicPaymentsPath("/webhooks/stripe"), true);
  assert.equal(isPublicPaymentsPath("/orders/order-1/refund"), false);
  assert.equal(isPublicPaymentsPath("/internal/test/stripe-webhook"), false);
});

test("requireInternalAuth fails closed when audience is missing", async () => {
  const res = makeResponse();
  const allowed = await requireInternalAuth(makeRequest(), res, {
    ...configuredAuth,
    INTERNAL_AUTH_AUDIENCE: ""
  });
  assert.equal(allowed, false);
  assert.equal(res.statusCode, 403);
  assert.deepEqual(res.body, { error: "internal_auth_not_configured" });
});

test("requireInternalAuth fails closed when allowlist is missing", async () => {
  const res = makeResponse();
  const allowed = await requireInternalAuth(makeRequest(), res, {
    ...configuredAuth,
    INTERNAL_ALLOWED_EMAILS: ""
  });
  assert.equal(allowed, false);
  assert.equal(res.statusCode, 403);
  assert.deepEqual(res.body, { error: "internal_auth_not_configured" });
});

test("requireInternalAuth rejects protected requests without bearer token", async () => {
  const res = makeResponse();
  const allowed = await requireInternalAuth(makeRequest(), res, configuredAuth);
  assert.equal(allowed, false);
  assert.equal(res.statusCode, 401);
  assert.deepEqual(res.body, { error: "missing_auth" });
});

test("requirePaymentsInternalAuth skips public paths and preflight", async () => {
  const middleware = requirePaymentsInternalAuth(configuredAuth);
  let nextCalls = 0;
  const next = () => {
    nextCalls += 1;
  };

  await middleware(makeRequest({ method: "GET", path: "/healthz" }), makeResponse(), next);
  await middleware(makeRequest({ path: "/webhooks/stripe" }), makeResponse(), next);
  await middleware(makeRequest({ method: "OPTIONS", path: "/orders/order-1/refund" }), makeResponse(), next);

  assert.equal(nextCalls, 3);
});

test("requirePaymentsInternalAuth blocks protected paths when auth is not configured", async () => {
  const middleware = requirePaymentsInternalAuth({
    ...configuredAuth,
    INTERNAL_ALLOWED_EMAILS: ""
  });
  const res = makeResponse();
  let nextCalled = false;
  await middleware(makeRequest({ path: "/orders/order-1/refund" }), res, () => {
    nextCalled = true;
  });

  assert.equal(nextCalled, false);
  assert.equal(res.statusCode, 403);
  assert.deepEqual(res.body, { error: "internal_auth_not_configured" });
});
