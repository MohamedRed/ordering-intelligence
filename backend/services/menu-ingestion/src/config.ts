export const bucketEnv = process.env.MENU_BUCKET ?? process.env.STORAGE_BUCKET_MENUS;
export const topicEnv = process.env.MENU_INGEST_TOPIC ?? process.env.PUBSUB_TOPIC_MENU_INGEST;
export const PROJECT = process.env.GOOGLE_CLOUD_PROJECT ?? process.env.GCP_PROJECT;
export const IMAGE_REGION = process.env.IMAGE_REGION ?? 'global';
export const TEXT_REGION = process.env.TEXT_REGION ?? process.env.VERTEX_LOCATION ?? 'global';
export const VERTEX_PROJECT = process.env.VERTEX_PROJECT ?? PROJECT;
export const COMPOSITE_MODEL = process.env.COMPOSITE_MODEL ?? 'gemini-3-pro-image-preview';
export const ANALYSIS_MODEL = process.env.ANALYSIS_MODEL ?? 'gemini-3-pro-preview';
export const RENDER_MODEL = process.env.RENDER_MODEL ?? COMPOSITE_MODEL;
export const GEN_TIMEOUT_MS = Number(process.env.GEN_TIMEOUT_MS ?? 120_000);
// Shorter timeout to avoid Cloud Run handler stalls when image generation backs up.
export const RENDER_TIMEOUT_MS = Number(process.env.RENDER_TIMEOUT_MS ?? 60_000);
export const RENDER_RETRIES = 1;
export const RENDER_BASE_DELAY_MS = Number(process.env.RENDER_BASE_DELAY_MS ?? 10_000);
export const RENDER_MIN_INTERVAL_MS = Number(process.env.RENDER_MIN_INTERVAL_MS ?? 10_000);
export const AGENT_COMPOSITE_URL = process.env.AGENT_COMPOSITE_URL;
export const AGENT_ANALYSIS_URL = process.env.AGENT_ANALYSIS_URL;
export const AGENT_RETRIES = Number(process.env.AGENT_RETRIES ?? 3);
export const AGENT_BASE_DELAY_MS = Number(process.env.AGENT_BASE_DELAY_MS ?? 3000);
export const AGENT_QUEUE_COLLECTION = process.env.AGENT_QUEUE_COLLECTION ?? 'agent_jobs';
export const AGENT_QUEUE_WAIT_MS = Number(process.env.AGENT_QUEUE_WAIT_MS ?? 90_000);
export const AGENT_CONFIG_DOC = process.env.AGENT_CONFIG_DOC ?? 'agent_worker/config';
export const MENU_UPDATES_TOPIC =
  process.env.MENU_UPDATES_TOPIC ?? process.env.PUBSUB_TOPIC_MENU_UPDATES;
export const VERBOSE_LOGGING = process.env.VERBOSE_LOGGING === 'true';
export const ENVIRONMENT = process.env.ENVIRONMENT ?? process.env.NODE_ENV ?? 'dev';
// In dev we always want call-level visibility to debug runaway spend / retries.
export const LOG_GENAI_SUCCESS = VERBOSE_LOGGING || ENVIRONMENT === 'dev';
