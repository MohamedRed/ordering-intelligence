const DEFAULT_TIMEOUT_MS = 20000;

const urls = [
  { name: 'consumer', env: 'CONSUMER_APP_URL' },
  { name: 'business', env: 'BUSINESS_APP_URL' },
  { name: 'driver', env: 'DRIVER_APP_URL' },
  { name: 'admin', env: 'ADMIN_APP_URL' },
];

const channelGatewayBase = process.env.CHANNEL_GATEWAY_BASE_URL;

const missing = urls.filter((item) => !process.env[item.env]);
if (missing.length > 0) {
  console.error(`Missing URL env vars: ${missing.map((m) => m.env).join(', ')}`);
  process.exit(1);
}

const fetchWithTimeout = async (url, timeoutMs = DEFAULT_TIMEOUT_MS) => {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: controller.signal });
    return res;
  } finally {
    clearTimeout(timeout);
  }
};

const assertFlutterIndex = async (name, url) => {
  const res = await fetchWithTimeout(url);
  if (!res.ok) {
    throw new Error(`${name} app returned ${res.status} at ${url}`);
  }
  const html = await res.text();
  const looksLikeFlutter = html.includes('flutter_bootstrap') || html.includes('flutter.js');
  if (!looksLikeFlutter) {
    throw new Error(`${name} app did not look like a Flutter web index at ${url}`);
  }
  console.log(`✓ ${name} app responded with Flutter index`);
};

const buildHealthUrls = (baseUrl) => {
  const candidates = [];
  const trimmed = baseUrl.replace(/\/$/, '');
  candidates.push(`${trimmed}/healthz`);
  try {
    const parsed = new URL(baseUrl);
    const originHealth = `${parsed.origin}/healthz`;
    if (!candidates.includes(originHealth)) {
      candidates.push(originHealth);
    }
    const originHealthSlash = `${parsed.origin}/healthz/`;
    if (!candidates.includes(originHealthSlash)) {
      candidates.push(originHealthSlash);
    }
  } catch (err) {
    throw new Error(`CHANNEL_GATEWAY_BASE_URL is invalid: ${baseUrl}`);
  }
  return candidates;
};

const assertChannelGateway = async () => {
  if (!channelGatewayBase) {
    console.log('CHANNEL_GATEWAY_BASE_URL not set; skipping API health check.');
    return;
  }
  const healthUrls = buildHealthUrls(channelGatewayBase);
  let lastFailure = null;
  for (const url of healthUrls) {
    try {
      const res = await fetchWithTimeout(url);
      if (res.ok) {
        console.log(`✓ channel-gateway healthz responded at ${url}`);
        return;
      }
      lastFailure = `${res.status} at ${url}`;
    } catch (err) {
      lastFailure = err?.message ?? String(err);
    }
  }
  throw new Error(`channel-gateway healthz failed (${lastFailure})`);
};

const run = async () => {
  for (const item of urls) {
    await assertFlutterIndex(item.name, process.env[item.env]);
  }
  await assertChannelGateway();
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
