import { DEFAULT_TIMEOUT_MS } from './ui_smoke_constants.mjs';

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

export const enableSemantics = async (page) => {
  const waitForSemanticsRoot = () =>
    page.waitForFunction(() => {
      const findNode = (selector) =>
        document.querySelector(selector)
        || document.querySelector('flutter-view')?.shadowRoot?.querySelector(selector);
      return Boolean(findNode('flt-semantics'));
    }, { timeout: DEFAULT_TIMEOUT_MS });

  try {
    await waitForSemanticsRoot();
    return;
  } catch (_) {
    // Fall through to trigger the semantics placeholder.
  }

  try {
    await page.waitForFunction(() => {
      const findNode = (selector) =>
        document.querySelector(selector)
        || document.querySelector('flutter-view')?.shadowRoot?.querySelector(selector);
      return Boolean(findNode('flt-semantics-placeholder'));
    }, { timeout: DEFAULT_TIMEOUT_MS });
  } catch (err) {
    throw new Error('Flutter semantics placeholder did not appear.');
  }

  await revealSemanticsPlaceholder(page);
  try {
    await page.click('flt-semantics-placeholder', { timeout: DEFAULT_TIMEOUT_MS });
  } catch (_) {
    // If Playwright actionability fails, fall back to JS click.
  }
  await dispatchPlaceholderClick(page);

  await waitForSemanticsRoot();
};
