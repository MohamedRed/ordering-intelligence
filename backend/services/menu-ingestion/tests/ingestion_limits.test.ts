import {
  assertFilesWithinPageLimit,
  IngestionLimitError,
  loadMenuIngestionLimits,
  parseRequestedPageCount,
} from '../src/ingestion_limits';

describe('menu ingestion limits', () => {
  it('loads defaults and positive integer overrides', () => {
    expect(loadMenuIngestionLimits({} as NodeJS.ProcessEnv)).toEqual({
      maxPages: 5,
      maxItemsPerPage: 40,
      maxTotalItems: 120,
    });
    expect(
      loadMenuIngestionLimits({
        MENU_MAX_PAGES: '7',
        MENU_MAX_ITEMS_PER_PAGE: '20',
        MENU_MAX_TOTAL_ITEMS: '80',
      } as NodeJS.ProcessEnv),
    ).toEqual({
      maxPages: 7,
      maxItemsPerPage: 20,
      maxTotalItems: 80,
    });
  });

  it('rejects invalid limit overrides at startup', () => {
    expect(() =>
      loadMenuIngestionLimits({ MENU_MAX_PAGES: '0' } as NodeJS.ProcessEnv),
    ).toThrow(/MENU_MAX_PAGES must be a positive integer/);
    expect(() =>
      loadMenuIngestionLimits({ MENU_MAX_ITEMS_PER_PAGE: '1.5' } as NodeJS.ProcessEnv),
    ).toThrow(/MENU_MAX_ITEMS_PER_PAGE must be a positive integer/);
  });

  it('validates requested upload page counts', () => {
    const limits = { maxPages: 2, maxItemsPerPage: 40, maxTotalItems: 120 };
    expect(parseRequestedPageCount(2, limits)).toBe(2);
    expect(() => parseRequestedPageCount(3, limits)).toThrow(IngestionLimitError);
    expect(() => parseRequestedPageCount('1.5', limits)).toThrow(/pageCount must be an integer/);
  });

  it('rejects over-limit processing jobs', () => {
    const limits = { maxPages: 2, maxItemsPerPage: 40, maxTotalItems: 120 };
    expect(() => assertFilesWithinPageLimit(['p1.jpg', 'p2.jpg'], limits)).not.toThrow();
    expect(() =>
      assertFilesWithinPageLimit(['p1.jpg', 'p2.jpg', 'p3.jpg'], limits),
    ).toThrow(/maximum is 2/);
  });
});
