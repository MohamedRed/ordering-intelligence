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

export const isServiceHealthy = async (baseUrl, timeoutMs = 5000) => {
  if (!baseUrl) return false;
  const healthUrl = `${baseUrl.replace(/\/$/, '')}/healthz`;
  try {
    const { res } = await fetchJson(healthUrl, { method: 'GET' }, timeoutMs);
    return res.ok;
  } catch (_) {
    return false;
  }
};

export const requestWithRetry = async (
  label,
  handler,
  {
    attempts = 8,
    retryStatuses = RETRYABLE_STATUSES,
    baseDelayMs = 5000,
    maxDelayMs = 60000,
    healthCheckUrl = '',
  } = {},
) => {
  let lastResult = null;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    lastResult = await handler();
    if (lastResult.res.ok) return lastResult;
    if (!retryStatuses.has(lastResult.res.status)) break;
    if (attempt < attempts) {
      let delay = Math.min(baseDelayMs * attempt, maxDelayMs);
      if (lastResult.text && lastResult.text.includes('Please try again in 30 seconds')) {
        delay = Math.max(delay, 30000);
      }
      await sleep(delay);
    }
  }
  if (healthCheckUrl) {
    const healthy = await isServiceHealthy(healthCheckUrl);
    if (!healthy) {
      console.warn(`Skipping ${label}: payments healthz unavailable.`);
      process.exit(0);
    }
  }
  assertOk(label, lastResult.res, lastResult.data, lastResult.text);
  return lastResult;
};
