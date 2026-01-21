import { DEFAULT_TIMEOUT_MS } from './ui_smoke_constants.mjs';
import { captureDomDiagnostics } from './ui_smoke_diagnostics.mjs';

const SEMANTICS_POLL_MS = 1500;
const SEMANTICS_PLACEHOLDER_TIMEOUT_MS = 20000;
const SEMANTICS_ENABLE_TIMEOUT_MS = DEFAULT_TIMEOUT_MS;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const hasNode = (selector, root) => Boolean(root?.querySelector(selector));

const revealSemanticsPlaceholder = async (page) => {
  await page.evaluate(() => {
    const findNode = (selector) =>
      document.querySelector(selector)
      || document.querySelector('flutter-view')?.shadowRoot?.querySelector(selector);
    const node = findNode('flt-semantics-placeholder');
    if (!node) return;
    Object.assign(node.style, {
      position: 'fixed',
      left: '16px',
      top: '16px',
      width: '32px',
      height: '32px',
      zIndex: '2147483647',
      display: 'block',
      visibility: 'visible',
      opacity: '0.01',
      pointerEvents: 'auto',
    });
  });
};

const dispatchPlaceholderClick = async (page) => {
  await page.evaluate(() => {
    const findNode = (selector) =>
      document.querySelector(selector)
      || document.querySelector('flutter-view')?.shadowRoot?.querySelector(selector);
    const node = findNode('flt-semantics-placeholder');
    if (!node) return;
    node.focus();
    node.click();
    node.dispatchEvent(
      new MouseEvent('click', { bubbles: true, cancelable: true, view: window }),
    );
  });
};

const pollForSemantics = async (page, timeoutMs) => {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const found = await page.evaluate(() => {
      const findNode = (selector) =>
        document.querySelector(selector)
        || document.querySelector('flutter-view')?.shadowRoot?.querySelector(selector);
      return Boolean(findNode('flt-semantics'));
    });
    if (found) return true;
    await sleep(SEMANTICS_POLL_MS);
  }
  return false;
};

const waitForPlaceholder = async (page, timeoutMs) => {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const found = await page.evaluate(() => {
      const findNode = (selector) =>
        document.querySelector(selector)
        || document.querySelector('flutter-view')?.shadowRoot?.querySelector(selector);
      return Boolean(findNode('flt-semantics-placeholder'));
    });
    if (found) return true;
    await sleep(SEMANTICS_POLL_MS);
  }
  return false;
};

export const enableSemantics = async (page, appName) => {
  if (await pollForSemantics(page, SEMANTICS_POLL_MS * 2)) {
    return;
  }

  console.log(`[${appName}] Waiting for semantics placeholder...`);
  const placeholderFound = await waitForPlaceholder(page, SEMANTICS_PLACEHOLDER_TIMEOUT_MS);
  if (!placeholderFound) {
    await captureDomDiagnostics(page, appName);
    throw new Error('Flutter semantics placeholder did not appear.');
  }

  await revealSemanticsPlaceholder(page);
  try {
    await page.click('flt-semantics-placeholder', {
      timeout: DEFAULT_TIMEOUT_MS,
      force: true,
    });
  } catch (_) {
    // If Playwright actionability fails, fall back to JS click.
  }

  const deadline = Date.now() + SEMANTICS_ENABLE_TIMEOUT_MS;
  while (Date.now() < deadline) {
    await dispatchPlaceholderClick(page);
    if (await pollForSemantics(page, SEMANTICS_POLL_MS)) {
      console.log(`[${appName}] Semantics enabled.`);
      return;
    }
  }

  await captureDomDiagnostics(page, appName);
  throw new Error('Flutter semantics did not attach within the timeout.');
};
