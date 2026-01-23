import path from 'node:path';

const toPositiveInt = (value, fallback) => {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return fallback;
  return Math.floor(parsed);
};

export const DEFAULT_TIMEOUT_MS = 60000;
export const HOSTING_READY_TIMEOUT_MS = toPositiveInt(
  process.env.HOSTING_READY_TIMEOUT_MS,
  180000,
);
export const HOSTING_READY_INTERVAL_MS = toPositiveInt(
  process.env.HOSTING_READY_INTERVAL_MS,
  10000,
);
export const ARTIFACT_DIR = path.join('tests', 'integration', 'artifacts');
