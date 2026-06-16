export type MenuIngestionLimits = {
  maxPages: number;
  maxItemsPerPage: number;
  maxTotalItems: number;
};

export class IngestionLimitError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly details: Record<string, number | string> = {},
  ) {
    super(message);
    this.name = 'IngestionLimitError';
  }
}

const DEFAULT_LIMITS: MenuIngestionLimits = {
  maxPages: 5,
  maxItemsPerPage: 40,
  maxTotalItems: 120,
};

function readPositiveInteger(
  env: NodeJS.ProcessEnv,
  name: string,
  fallback: number,
): number {
  const raw = env[name];
  if (raw == null || raw.trim() === '') return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1) {
    throw new Error(`${name} must be a positive integer`);
  }
  return value;
}

export function loadMenuIngestionLimits(
  env: NodeJS.ProcessEnv = process.env,
): MenuIngestionLimits {
  return {
    maxPages: readPositiveInteger(env, 'MENU_MAX_PAGES', DEFAULT_LIMITS.maxPages),
    maxItemsPerPage: readPositiveInteger(
      env,
      'MENU_MAX_ITEMS_PER_PAGE',
      DEFAULT_LIMITS.maxItemsPerPage,
    ),
    maxTotalItems: readPositiveInteger(
      env,
      'MENU_MAX_TOTAL_ITEMS',
      DEFAULT_LIMITS.maxTotalItems,
    ),
  };
}

export const ingestionLimits = loadMenuIngestionLimits();

export function parseRequestedPageCount(
  value: unknown,
  limits: MenuIngestionLimits = ingestionLimits,
): number {
  const pageCount = Number(value);
  if (!Number.isInteger(pageCount) || pageCount < 1) {
    throw new IngestionLimitError(
      'invalid_page_count',
      `pageCount must be an integer between 1 and ${limits.maxPages}`,
      { maxPages: limits.maxPages },
    );
  }
  if (pageCount > limits.maxPages) {
    throw new IngestionLimitError(
      'too_many_pages',
      `pageCount exceeds the maximum of ${limits.maxPages}`,
      { pageCount, maxPages: limits.maxPages },
    );
  }
  return pageCount;
}

export function assertFilesWithinPageLimit(
  files: unknown,
  limits: MenuIngestionLimits = ingestionLimits,
): asserts files is string[] {
  if (!Array.isArray(files)) {
    throw new IngestionLimitError('invalid_files', 'files must be an array');
  }
  if (files.length > limits.maxPages) {
    throw new IngestionLimitError(
      'too_many_pages',
      `ingest job has ${files.length} files, maximum is ${limits.maxPages}`,
      { fileCount: files.length, maxPages: limits.maxPages },
    );
  }
}
