import { writeFile } from 'node:fs/promises';
import path from 'node:path';

import { ARTIFACT_DIR } from './ui_smoke_constants.mjs';

export const attachPageLogging = (page) => {
  const logs = [];
  const pushLog = (entry) => {
    logs.push(`[${new Date().toISOString()}] ${entry}`);
  };
  page.on('console', (msg) => {
    const type = msg.type();
    pushLog(`[console:${type}] ${msg.text()}`);
  });
  page.on('pageerror', (err) => {
    pushLog(`[pageerror] ${err.message || err}`);
  });
  page.on('requestfailed', (request) => {
    const failure = request.failure();
    pushLog(
      `[requestfailed] ${request.method()} ${request.url()} ${failure?.errorText ?? ''}`.trim(),
    );
  });
  page.on('response', (response) => {
    const status = response.status();
    const url = response.url();
    if (status >= 400) {
      pushLog(`[response:${status}] ${response.request().method()} ${url}`);
      return;
    }
    if (/flutter_bootstrap\\.js|main\\.dart\\.js|canvaskit|skwasm|flutter_service_worker/.test(url)) {
      pushLog(`[response:${status}] ${url}`);
    }
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
