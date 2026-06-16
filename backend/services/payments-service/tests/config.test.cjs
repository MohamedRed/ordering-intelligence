const assert = require("node:assert/strict");
const test = require("node:test");

const { resolveCorsOrigins } = require("../dist/config");
const { buildCorsOptions } = require("../dist/cors");

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
