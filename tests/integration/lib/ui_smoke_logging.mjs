import { writeFile } from 'node:fs/promises';
import path from 'node:path';

import { ARTIFACT_DIR } from './ui_smoke_constants.mjs';

export const attachPageLogging = (page) => {
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

export const flushLogs = async (logs, appName) => {
  if (logs.length === 0) return;
  await writeFile(
    path.join(ARTIFACT_DIR, `${appName}-console.txt`),
    `${logs.join('\n')}\n`,
  );
};

export const captureFailure = async (page, appName) => {
  try {
    await page.screenshot({
      path: path.join(ARTIFACT_DIR, `${appName}-error.png`),
      fullPage: true,
    });
  } catch (_) {}
};
