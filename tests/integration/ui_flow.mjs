import { chromium } from 'playwright';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';

const DEFAULT_TIMEOUT_MS = 30000;
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

const assertText = async (page, text) => {
  await page.getByText(text, { exact: false }).first().waitFor({
    state: 'visible',
    timeout: DEFAULT_TIMEOUT_MS,
  });
};

const run = async () => {
  await mkdir(ARTIFACT_DIR, { recursive: true });
  const browser = await chromium.launch({ headless: true });

  try {
    for (const app of apps) {
      const url = process.env[app.env];
      const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
      await page.goto(url, { waitUntil: 'domcontentloaded' });
      await page.waitForSelector('flt-glass-pane, flutter-view', {
        timeout: DEFAULT_TIMEOUT_MS,
      });
      for (const text of app.expected) {
        await assertText(page, text);
      }
      await page.screenshot({
        path: path.join(ARTIFACT_DIR, `${app.name}.png`),
        fullPage: true,
      });
      await page.close();
      console.log(`✓ ${app.name} UI flow ok`);
    }
  } finally {
    await browser.close();
  }
};

run().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
