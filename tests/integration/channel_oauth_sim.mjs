import { getIdentityToken } from './lib/gcloud_tokens.mjs';

const DEFAULT_TIMEOUT_MS = 20000;
const baseUrl = process.env.CHANNEL_GATEWAY_BASE_URL;
const suffix = (process.env.FIRESTORE_SUFFIX || 'ci').trim();
const storeId = `test-store-${suffix}`;

if (!baseUrl) {
  console.error('Missing CHANNEL_GATEWAY_BASE_URL env var.');
  process.exit(1);
}

const apiBase = baseUrl.replace(/\/$/, '');
const token = getIdentityToken(apiBase);

const fetchJson = async (url, options = {}) => {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), DEFAULT_TIMEOUT_MS);
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

const assertOk = (label, res, data, text) => {
  if (!res.ok) {
    const payload = data ? JSON.stringify(data) : text || 'no body';
    throw new Error(`${label} failed: ${res.status} ${payload}`);
  }
};

const identityPathFor = (channel) => {
  switch (channel) {
    case 'discord_webapp':
      return '/discord/webapp/identity';
    case 'snapchat_webapp':
      return '/snapchat/webapp/identity';
    default:
      return '/telegram/webapp/identity';
  }
};

const createSession = async (channel) => {
  const payload = {
    channel,
    userId: `ci-${channel}-${suffix}`,
    displayName: `CI ${channel}`,
    storeId
  };
  const { res, data, text } = await fetchJson(`${apiBase}/internal/test/webapp/session`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`
    },
    body: JSON.stringify(payload)
  });
  assertOk(`create session ${channel}`, res, data, text);
  return data?.sessionId;
};

const run = async () => {
  const channels = ['telegram_webapp', 'discord_webapp', 'snapchat_webapp'];
  for (const channel of channels) {
    const sessionId = await createSession(channel);
    if (!sessionId) {
      throw new Error(`missing sessionId for ${channel}`);
    }
    const path = identityPathFor(channel);
    const { res, data, text } = await fetchJson(`${apiBase}${path}?sessionId=${encodeURIComponent(sessionId)}`, {
      method: 'GET'
    });
    assertOk(`identity ${channel}`, res, data, text);
  }
  console.log('✓ channel webapp oauth sim ok');
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
