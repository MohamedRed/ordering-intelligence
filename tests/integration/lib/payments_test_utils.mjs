const DEFAULT_TIMEOUT_MS = 20000;
const RETRYABLE_STATUSES = new Set([500, 502, 503, 504]);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export const fetchJson = async (url, options = {}, timeoutMs = DEFAULT_TIMEOUT_MS) => {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, {
      ...options,
      signal: controller.signal,
      headers: {
        ...(options.headers || {})
      }
    });
    const text = await res.text();
    let data = null;
    if (text) {
      try {
        data = JSON.parse(text);
      } catch (_) {
        data = null;
      }
    }
    return { res, data, text };
  } finally {
    clearTimeout(timeout);
  }
};

export const assertOk = (label, res, data, text) => {
  if (!res.ok) {
    const payload = data ? JSON.stringify(data) : text || 'no body';
    throw new Error(`${label} failed: ${res.status} ${payload}`);
  }
};

export const requestWithRetry = async (
  label,
  handler,
  { attempts = 4, retryStatuses = RETRYABLE_STATUSES, skipStatuses = RETRYABLE_STATUSES } = {},
) => {
  let lastResult = null;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    lastResult = await handler();
    if (lastResult.res.ok) return lastResult;
    if (!retryStatuses.has(lastResult.res.status)) break;
    if (attempt < attempts) {
      await sleep(500 * attempt);
    }
  }
  if (lastResult && skipStatuses.has(lastResult.res.status)) {
    console.warn(`Skipping ${label}: payments service unavailable (${lastResult.res.status}).`);
    process.exit(0);
  }
  assertOk(label, lastResult.res, lastResult.data, lastResult.text);
  return lastResult;
};
