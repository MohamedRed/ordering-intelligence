import { chromium } from 'playwright';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { ARTIFACT_DIR, DEFAULT_TIMEOUT_MS } from './lib/ui_smoke_constants.mjs';
import { assertText } from './lib/ui_smoke_assertions.mjs';
import { waitForHostingReady } from './lib/ui_smoke_hosting.mjs';
import {
  attachPageLogging,
  captureFailure,
  flushLogs,
} from './lib/ui_smoke_logging.mjs';
import { enableSemantics } from './lib/ui_smoke_semantics.mjs';
const apps = [
  {
    name: 'consumer',
    env: 'CONSUMER_APP_URL',
    expected: ['Sign in', 'Choose a social account'],
  },
  {
    name: 'business',
    env: 'BUSINESS_APP_URL',
    expected: ['Sign In', 'manage orders and menu'],
  },
  {
    name: 'admin',
    env: 'ADMIN_APP_URL',
    expected: ['Sign in', 'manage alerts'],
  },
  {
    name: 'driver',
    env: 'DRIVER_APP_URL',
    expected: ['Driver sign in', 'Send code'],
  },
];
const missing = apps.filter((app) => !process.env[app.env]);
if (missing.length > 0) {
  console.error(`Missing URL env vars: ${missing.map((m) => m.env).join(', ')}`);
  process.exit(1);
}

const installFirstFrameHook = async (page) => {
  await page.addInitScript(() => {
    window.__flutterFirstFrame = false;
    window.addEventListener(
      'flutter-first-frame',
      () => {
        window.__flutterFirstFrame = true;
      },
      { once: true },
    );
  });
};

const run = async () => {
  await mkdir(ARTIFACT_DIR, { recursive: true });
  const browser = await chromium.launch({ headless: true });

  try {
    for (const app of apps) {
      const url = process.env[app.env];
      await waitForHostingReady(url, app.name);
      const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
      const logs = attachPageLogging(page);
      await installFirstFrameHook(page);
      try {
        await page.goto(url, { waitUntil: 'load' });
        await page.waitForSelector('flt-glass-pane, flutter-view', {
          timeout: DEFAULT_TIMEOUT_MS,
        });
        await page.waitForFunction(() => window.__flutterFirstFrame === true, {
          timeout: DEFAULT_TIMEOUT_MS,
        });
        await enableSemantics(page);
        for (const text of app.expected) {
          await assertText(page, text);
        }
        await page.screenshot({
          path: path.join(ARTIFACT_DIR, `${app.name}.png`),
          fullPage: true,
        });
        console.log(`✓ ${app.name} UI flow ok`);
      } catch (err) {
        await captureFailure(page, app.name);
        await flushLogs(logs, app.name);
        throw err;
      } finally {
        await flushLogs(logs, app.name);
        await page.close();
      }
    }
  } finally {
    await browser.close();
  }
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
