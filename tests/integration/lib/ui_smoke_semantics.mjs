import { DEFAULT_TIMEOUT_MS } from './ui_smoke_constants.mjs';
import { captureDomDiagnostics } from './ui_smoke_diagnostics.mjs';

const SEMANTICS_POLL_MS = 1500;
const SEMANTICS_PLACEHOLDER_TIMEOUT_MS = 20000;
const SEMANTICS_ENABLE_TIMEOUT_MS = DEFAULT_TIMEOUT_MS;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const revealSemanticsPlaceholder = async (page) => {
  await page.evaluate(() => {
    const resolveRoots = () => {
      const roots = [document];
      const flutterView = document.querySelector('flutter-view');
      if (flutterView) roots.push(flutterView);
      const glassPane = document.querySelector('flt-glass-pane');
      if (glassPane?.shadowRoot) roots.push(glassPane.shadowRoot);
      const semanticsHost = document.querySelector('flt-semantics-host');
      if (semanticsHost) roots.push(semanticsHost);
      return roots;
    };
    const findNode = (selector) => {
      const roots = resolveRoots();
      for (const root of roots) {
        const node = root.querySelector(selector);
        if (node) return node;
      }
      return null;
    };
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
    const resolveRoots = () => {
      const roots = [document];
      const flutterView = document.querySelector('flutter-view');
      if (flutterView) roots.push(flutterView);
      const glassPane = document.querySelector('flt-glass-pane');
      if (glassPane?.shadowRoot) roots.push(glassPane.shadowRoot);
      const semanticsHost = document.querySelector('flt-semantics-host');
      if (semanticsHost) roots.push(semanticsHost);
      return roots;
    };
    const findNode = (selector) => {
      const roots = resolveRoots();
      for (const root of roots) {
        const node = root.querySelector(selector);
        if (node) return node;
      }
      return null;
    };
    const node = findNode('flt-semantics-placeholder');
    if (!node) return;
    node.focus();
    const rect = node.getBoundingClientRect();
    const eventInit = {
      bubbles: true,
      cancelable: true,
      view: window,
      clientX: rect.left + 4,
      clientY: rect.top + 4,
    };
    node.dispatchEvent(new PointerEvent('pointerdown', eventInit));
    node.dispatchEvent(new PointerEvent('pointerup', eventInit));
    node.dispatchEvent(new MouseEvent('mousedown', eventInit));
    node.dispatchEvent(new MouseEvent('mouseup', eventInit));
    node.dispatchEvent(new MouseEvent('click', eventInit));
    node.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
    node.dispatchEvent(new KeyboardEvent('keyup', { key: 'Enter', bubbles: true }));
  });
};

const pollForSemantics = async (page, timeoutMs) => {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const found = await page.evaluate(() => {
      const resolveRoots = () => {
        const roots = [document];
        const flutterView = document.querySelector('flutter-view');
        if (flutterView) roots.push(flutterView);
        const glassPane = document.querySelector('flt-glass-pane');
        if (glassPane?.shadowRoot) roots.push(glassPane.shadowRoot);
        const semanticsHost = document.querySelector('flt-semantics-host');
        if (semanticsHost) roots.push(semanticsHost);
        return roots;
      };
      const findNode = (selector) => {
        const roots = resolveRoots();
        for (const root of roots) {
          const node = root.querySelector(selector);
          if (node) return node;
        }
        return null;
      };
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
      const resolveRoots = () => {
        const roots = [document];
        const flutterView = document.querySelector('flutter-view');
        if (flutterView) roots.push(flutterView);
        const glassPane = document.querySelector('flt-glass-pane');
        if (glassPane?.shadowRoot) roots.push(glassPane.shadowRoot);
        const semanticsHost = document.querySelector('flt-semantics-host');
        if (semanticsHost) roots.push(semanticsHost);
        return roots;
      };
      const findNode = (selector) => {
        const roots = resolveRoots();
        for (const root of roots) {
          const node = root.querySelector(selector);
          if (node) return node;
        }
        return null;
      };
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

  try {
    const box = await page.locator('flt-semantics-placeholder').first().boundingBox();
    if (box) {
      await page.mouse.click(box.x + 6, box.y + 6);
    }
  } catch (_) {
    // Ignore locator failures and rely on JS dispatches below.
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
