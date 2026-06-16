export const DEFAULT_MENU_MAX_PAGES = 5;

export function resolveMenuMaxPages(env: NodeJS.ProcessEnv = process.env): number {
  const raw = env.MENU_MAX_PAGES;
  if (raw == null || raw.trim() === '') return DEFAULT_MENU_MAX_PAGES;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1) {
    throw new Error('MENU_MAX_PAGES must be a positive integer');
  }
  return value;
}

export const MENU_MAX_PAGES = resolveMenuMaxPages();

export function validateMenuFlyerCount(
  flyerCount: number,
  maxPages = MENU_MAX_PAGES,
): string | undefined {
  if (!Number.isInteger(flyerCount) || flyerCount < 1) {
    return 'At least one menu flyer is required';
  }
  if (flyerCount > maxPages) {
    return `Menu ingestion accepts at most ${maxPages} flyers per job`;
  }
  return undefined;
}
