import path from 'node:path';

export const DEFAULT_TIMEOUT_MS = 60000;
export const HOSTING_READY_TIMEOUT_MS = 180000;
export const HOSTING_READY_INTERVAL_MS = 10000;
export const ARTIFACT_DIR = path.join('tests', 'integration', 'artifacts');
