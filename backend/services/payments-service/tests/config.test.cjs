const assert = require("node:assert/strict");
const test = require("node:test");

const { getConfig, resolveCorsOrigins } = require("../dist/config");
const { buildCorsOptions } = require("../dist/cors");

const CONFIG_ENV_KEYS = [
  "PORT",
  "ENVIRONMENT",
  "CORS_ORIGINS",
  "FIREBASE_PROJECT_ID",
  "STRIPE_SECRET_KEY",
  "STRIPE_PUBLISHABLE_KEY",
  "STRIPE_WEBHOOK_SECRET",
  "STRIPE_WEBHOOK_ALLOWED_EVENTS",
  "ORDER_SERVICE_URL",
  "NOTIFICATION_SERVICE_URL",
  "INTERNAL_AUTH_AUDIENCE",
  "INTERNAL_ALLOWED_EMAILS"
];

function withConfigEnv(overrides, fn) {
  const previous = new Map(CONFIG_ENV_KEYS.map((key) => [key, process.env[key]]));
  for (const key of CONFIG_ENV_KEYS) {
    delete process.env[key];
  }
  for (const [key, value] of Object.entries(overrides)) {
    process.env[key] = value;
  }
  try {
    return fn();
  } finally {
    for (const key of CONFIG_ENV_KEYS) {
      const value = previous.get(key);
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  }
}

test("resolveCorsOrigins requires explicit origins", () => {
  assert.throws(
    () => resolveCorsOrigins("", "development"),
    /CORS_ORIGINS is required/
  );
});

test("resolveCorsOrigins rejects wildcard origins in production-like environments", () => {
  assert.throws(
    () => resolveCorsOrigins("https://checkout.example.com,*", "production"),
    /Wildcard CORS origins are not allowed/
  );
  assert.throws(
    () => resolveCorsOrigins("*", "staging"),
    /Wildcard CORS origins are not allowed/
  );
});

test("resolveCorsOrigins normalizes and de-duplicates http origins", () => {
  assert.deepEqual(
    resolveCorsOrigins(
      "https://checkout.example.com/,https://checkout.example.com,http://localhost:4000",
      "development"
    ),
    ["https://checkout.example.com", "http://localhost:4000"]
  );
});

test("resolveCorsOrigins rejects paths and non-http origins", () => {
  assert.throws(
    () => resolveCorsOrigins("https://checkout.example.com/pay", "development"),
    /Include only scheme, host, and optional port/
  );
  assert.throws(
    () => resolveCorsOrigins("file://checkout.example.com", "development"),
    /Only http and https origins are supported/
  );
});

test("getConfig requires internal auth settings in production-like environments", () => {
  withConfigEnv(
    {
      ENVIRONMENT: "staging",
      CORS_ORIGINS: "https://checkout.example.com",
      FIREBASE_PROJECT_ID: "ordering-intelligence-test",
      STRIPE_SECRET_KEY: "sk_test_123",
      ORDER_SERVICE_URL: "https://orders.example.com"
    },
    () => {
      assert.throws(
        () => getConfig(),
        /INTERNAL_AUTH_AUDIENCE and INTERNAL_ALLOWED_EMAILS are required/
      );
    }
  );
});

test("buildCorsOptions allows configured origins and blocks unknown browser origins", async () => {
  const options = buildCorsOptions(["https://checkout.example.com"]);
  const origin = options.origin;
  assert.equal(typeof origin, "function");

  await new Promise((resolve, reject) => {
    origin("https://checkout.example.com", (error, allowed) => {
      try {
        assert.ifError(error);
        assert.equal(allowed, true);
        resolve();
      } catch (assertionError) {
        reject(assertionError);
      }
    });
  });

  await new Promise((resolve, reject) => {
    origin(undefined, (error, allowed) => {
      try {
        assert.ifError(error);
        assert.equal(allowed, true);
        resolve();
      } catch (assertionError) {
        reject(assertionError);
      }
    });
  });

  await new Promise((resolve, reject) => {
    origin("https://evil.example.com", (error) => {
      try {
        assert.match(error.message, /CORS blocked/);
        resolve();
      } catch (assertionError) {
        reject(assertionError);
      }
    });
  });
});
