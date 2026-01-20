import { chromium } from 'playwright';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

const DEFAULT_TIMEOUT_MS = 60000;
const HOSTING_READY_TIMEOUT_MS = 180000;
const HOSTING_READY_INTERVAL_MS = 10000;
const ARTIFACT_DIR = path.join('tests', 'integration', 'artifacts');

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

const toAttributeSelector = (text) => text.replace(/"/g, '\\"');
const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const toTextMatcher = (text) => new RegExp(escapeRegExp(text), 'i');

const attachPageLogging = (page) => {
  const logs = [];
  page.on('console', (msg) => {
    const type = msg.type();
    if (type === 'warning' || type === 'error') {
      logs.push(`[console:${type}] ${msg.text()}`);
    }
  });
  page.on('pageerror', (err) => {
    logs.push(`[pageerror] ${err.message || err}`);
  });
  return logs;
};

const flushLogs = async (logs, appName) => {
  if (logs.length === 0) return;
  await writeFile(
    path.join(ARTIFACT_DIR, `${appName}-console.txt`),
    `${logs.join('\n')}\n`,
  );
};

const waitForHostingReady = async (url, appName) => {
  const deadline = Date.now() + HOSTING_READY_TIMEOUT_MS;
  let lastStatus = 'no-response';
  while (Date.now() < deadline) {
    try {
      const response = await fetch(url, { redirect: 'follow' });
      const body = await response.text();
      const hasFlutterBootstrap = body.includes('flutter_bootstrap.js');
      const isPlaceholder = body.includes('Site Not Found') || body.includes('hosting documentation');
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
  throw new Error(`[${appName}] Hosting not ready after ${HOSTING_READY_TIMEOUT_MS / 1000}s.`);
};

const enableSemantics = async (page) => {
  const placeholder = page.locator('flt-semantics-placeholder');
  if (await placeholder.count()) {
    await page.evaluate(() => {
      const node = document.querySelector('flt-semantics-placeholder');
      node?.dispatchEvent(
        new MouseEvent('click', { bubbles: true, cancelable: true, view: window }),
      );
    });
    await page.waitForSelector('flt-semantics', {
      timeout: DEFAULT_TIMEOUT_MS,
      state: 'attached',
    });
  }
};

const assertText = async (page, text) => {
  const textMatcher = toTextMatcher(text);
  const ariaSelector = `[aria-label*="${toAttributeSelector(text)}" i]`;
  try {
    await Promise.any([
      page.getByText(textMatcher).first().waitFor({
        state: 'visible',
        timeout: DEFAULT_TIMEOUT_MS,
      }),
      page.locator(ariaSelector).first().waitFor({
        state: 'attached',
        timeout: DEFAULT_TIMEOUT_MS,
      }),
    ]);
  } catch (err) {
    throw new Error(`Timed out waiting for "${text}"`);
  }
};

const captureFailure = async (page, appName) => {
  try {
    await page.screenshot({
      path: path.join(ARTIFACT_DIR, `${appName}-error.png`),
      fullPage: true,
    });
  } catch (_) {}
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
