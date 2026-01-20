import { DEFAULT_TIMEOUT_MS } from './ui_smoke_constants.mjs';

const toAttributeSelector = (text) => text.replace(/"/g, '\\"');
const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const toTextMatcher = (text) => new RegExp(escapeRegExp(text), 'i');

export const assertText = async (page, text) => {
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
