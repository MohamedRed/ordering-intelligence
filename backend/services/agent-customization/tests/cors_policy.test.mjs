import assert from 'node:assert/strict';
import test from 'node:test';

import { buildCorsOptions, resolveCorsOrigins } from '../dist/cors_policy.js';

test('resolveCorsOrigins requires explicit configuration', () => {
  assert.throws(
    () => resolveCorsOrigins('', 'development'),
    /CORS_ORIGINS is required/,
  );
});

test('resolveCorsOrigins rejects wildcard in staging and production', () => {
  assert.throws(
    () => resolveCorsOrigins('*', 'staging'),
    /Wildcard CORS origins are not allowed/,
  );
  assert.throws(
    () => resolveCorsOrigins('https://admin.example.com,*', 'prod'),
    /Wildcard CORS origins are not allowed/,
  );
});

test('resolveCorsOrigins normalizes and de-duplicates origin URLs', () => {
  assert.deepEqual(
    resolveCorsOrigins(
      'https://admin.example.com/,https://admin.example.com,http://localhost:4000',
      'development',
    ),
    ['https://admin.example.com', 'http://localhost:4000'],
  );
});

test('resolveCorsOrigins rejects paths and unsupported schemes', () => {
  assert.throws(
    () => resolveCorsOrigins('https://admin.example.com/settings', 'development'),
    /Include only scheme, host, and optional port/,
  );
  assert.throws(
    () => resolveCorsOrigins('file://admin.example.com', 'development'),
    /Only http and https origins are supported/,
  );
});

test('buildCorsOptions allows configured origins and rejects unknown browser origins', async () => {
  const originHandler = buildCorsOptions(['https://admin.example.com']).origin;
  assert.equal(typeof originHandler, 'function');

  await new Promise((resolve, reject) => {
    originHandler('https://admin.example.com', (error, allowed) => {
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
    originHandler(undefined, (error, allowed) => {
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
    originHandler('https://unknown.example.com', (error) => {
      try {
        assert.match(error.message, /CORS blocked/);
        resolve();
      } catch (assertionError) {
        reject(assertionError);
      }
    });
  });
});
