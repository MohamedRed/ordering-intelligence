import {
  DEFAULT_MENU_MAX_PAGES,
  resolveMenuMaxPages,
  validateMenuFlyerCount,
} from './menu_ingestion_limits';

describe('onboarding menu ingestion limits', () => {
  it('resolves defaults and positive integer overrides', () => {
    expect(resolveMenuMaxPages({} as NodeJS.ProcessEnv)).toBe(DEFAULT_MENU_MAX_PAGES);
    expect(resolveMenuMaxPages({ MENU_MAX_PAGES: '8' } as NodeJS.ProcessEnv)).toBe(8);
  });

  it('rejects invalid limit overrides', () => {
    expect(() =>
      resolveMenuMaxPages({ MENU_MAX_PAGES: '0' } as NodeJS.ProcessEnv),
    ).toThrow(/MENU_MAX_PAGES must be a positive integer/);
    expect(() =>
      resolveMenuMaxPages({ MENU_MAX_PAGES: '2.5' } as NodeJS.ProcessEnv),
    ).toThrow(/MENU_MAX_PAGES must be a positive integer/);
  });

  it('validates flyer counts before creating ingestion jobs', () => {
    expect(validateMenuFlyerCount(1, 2)).toBeUndefined();
    expect(validateMenuFlyerCount(0, 2)).toMatch(/At least one/);
    expect(validateMenuFlyerCount(3, 2)).toMatch(/at most 2/);
  });
});
