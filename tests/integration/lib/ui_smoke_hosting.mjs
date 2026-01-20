import {
  HOSTING_READY_INTERVAL_MS,
  HOSTING_READY_TIMEOUT_MS,
} from './ui_smoke_constants.mjs';

export const waitForHostingReady = async (url, appName) => {
  const deadline = Date.now() + HOSTING_READY_TIMEOUT_MS;
  let lastStatus = 'no-response';
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url, { redirect: 'follow' });
      const body = await response.text();
      const hasFlutterBootstrap = body.includes('flutter_bootstrap.js');
      const isPlaceholder =
        body.includes('Site Not Found') || body.includes('hosting documentation');
      if (response.ok && hasFlutterBootstrap && !isPlaceholder) {
        return;
      }
      lastStatus = `status=${response.status} placeholder=${isPlaceholder} bootstrap=${hasFlutterBootstrap}`;
    } catch (err) {
      lastStatus = err?.message || String(err);
    }
    console.log(`[${appName}] Waiting for hosting (${lastStatus}).`);
    await new Promise((resolve) => setTimeout(resolve, HOSTING_READY_INTERVAL_MS));
  }
  throw new Error(
    `[${appName}] Hosting not ready after ${HOSTING_READY_TIMEOUT_MS / 1000}s.`,
  );
};
