import { DEFAULT_TIMEOUT_MS } from './ui_smoke_constants.mjs';

const revealSemanticsPlaceholder = async (page) => {
  await page.evaluate(() => {
    const node = document.querySelector('flt-semantics-placeholder');
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
    const node = document.querySelector('flt-semantics-placeholder');
    if (!node) return;
    node.focus();
    node.click();
    node.dispatchEvent(
      new MouseEvent('click', { bubbles: true, cancelable: true, view: window }),
    );
  });
};

export const enableSemantics = async (page) => {
  try {
    await page.waitForSelector('flt-semantics', {
      timeout: DEFAULT_TIMEOUT_MS,
      state: 'attached',
    });
    return;
  } catch (_) {
    // Fall through to trigger the semantics placeholder.
  }

  const placeholder = page.locator('flt-semantics-placeholder').first();
  try {
    await placeholder.waitFor({ state: 'attached', timeout: DEFAULT_TIMEOUT_MS });
  } catch (err) {
    throw new Error('Flutter semantics placeholder did not appear.');
  }

  await revealSemanticsPlaceholder(page);
  try {
    await placeholder.click({ timeout: DEFAULT_TIMEOUT_MS });
  } catch (_) {
    // If Playwright actionability fails, fall back to JS click.
  }
  await dispatchPlaceholderClick(page);

  await page.waitForSelector('flt-semantics', {
    timeout: DEFAULT_TIMEOUT_MS,
    state: 'attached',
  });
};
