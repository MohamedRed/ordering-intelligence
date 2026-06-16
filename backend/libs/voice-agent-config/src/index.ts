import fs from 'node:fs';
import path from 'node:path';

import {
  LoadVoiceAgentOptions,
  LoadedVoiceAgentConfig,
  LocationOverride,
  TelephonyRoutingConfig,
  TelephonyProvider,
  VoiceAgentConfig,
  VoiceAgentEnvironment,
} from './types';

const ENVIRONMENT_ALIASES: Record<string, VoiceAgentEnvironment> = {
  development: 'dev',
  dev: 'dev',
  local: 'dev',
  staging: 'staging',
  stage: 'staging',
  test: 'staging',
  production: 'prod',
  prod: 'prod',
};

export * from './types';

export const AVAILABLE_ENVIRONMENTS: VoiceAgentEnvironment[] = ['dev', 'staging', 'prod'];

export function inferVoiceAgentEnvironment(fromEnv: NodeJS.ProcessEnv = process.env): VoiceAgentEnvironment {
  const candidate =
    fromEnv.APP_ENV || fromEnv.APP_ENVIRONMENT || fromEnv.ENVIRONMENT || fromEnv.NODE_ENV || 'dev';
  const normalized = candidate.trim().toLowerCase();
  return ENVIRONMENT_ALIASES[normalized] ?? 'dev';
}

export function loadVoiceAgentConfig(
  options: LoadVoiceAgentOptions = {},
): LoadedVoiceAgentConfig {
  const environment = options.env ?? inferVoiceAgentEnvironment();
  const dirToUse = options.baseDir ?? path.resolve(process.cwd(), 'infra', 'voice-agents');
  const sourcePath = path.resolve(dirToUse, `${environment}.json`);

  if (!fs.existsSync(sourcePath)) {
    throw new Error(
      `Voice agent config not found for env "${environment}". Looked in ${sourcePath}. Set baseDir if configs live elsewhere.`,
    );
  }

  const raw = fs.readFileSync(sourcePath, 'utf-8');
  const parsed = JSON.parse(raw);
  const validated = validateVoiceAgentConfig(parsed, sourcePath);
  const clone = deepClone(validated);

  const locationCode = options.locationCode ?? process.env.VOICE_AGENT_LOCATION_CODE ?? options.fallbackLocationCode;
  let appliedLocationCode: string | undefined;
  if (locationCode && clone.locationOverrides?.[locationCode]) {
    applyLocationOverride(clone, clone.locationOverrides[locationCode]!);
    appliedLocationCode = locationCode;
  }

  if (options.overrides) {
    applyLocationOverride(clone, options.overrides as LocationOverride);
  }

  const { locationOverrides, ...exportable } = clone;

  return {
    ...(exportable as VoiceAgentConfig),
    environment,
    sourcePath,
    appliedLocationCode,
  };
}

/**
 * Load inbound telephony routing settings from environment variables.
 * This is intentionally simple so workers/agents can branch between
 * US first-party LiveKit PSTN numbers and third-party SIP trunks.
 */
export function loadTelephonyRouting(
  env: NodeJS.ProcessEnv = process.env,
): TelephonyRoutingConfig {
  const provider = (env.TELEPHONY_PROVIDER as TelephonyProvider | undefined) ?? 'sip-trunk';
  if (!['us-livekit-pstn', 'sip-trunk'].includes(provider)) {
    throw new Error(`Unsupported TELEPHONY_PROVIDER "${provider}". Expected "us-livekit-pstn" or "sip-trunk".`);
  }

  const number = env.TELEPHONY_NUMBER;
  const dispatchRuleId = env.TELEPHONY_DISPATCH_RULE_ID;
  const missing: string[] = [];
  if (!number) missing.push('TELEPHONY_NUMBER');
  if (!dispatchRuleId) missing.push('TELEPHONY_DISPATCH_RULE_ID');

  if (missing.length) {
    throw new Error(`Missing required telephony routing env vars: ${missing.join(', ')}`);
  }

  return {
    provider,
    number: number!,
    dispatchRuleId: dispatchRuleId!,
  };
}

function validateVoiceAgentConfig(config: any, sourcePath: string): VoiceAgentConfig {
  if (typeof config !== 'object' || config === null) {
    throw new Error(`Voice agent config in ${sourcePath} must be an object.`);
  }

  const requiredStrings: Array<[keyof VoiceAgentConfig, string]> = [['presetName', 'presetName']];
  for (const [key, label] of requiredStrings) {
    if (typeof config[key] !== 'string' || !config[key]) {
      throw new Error(`Missing required string "${label}" in ${sourcePath}`);
    }
  }

  if (!isObject(config.llm) || typeof config.llm.provider !== 'string' || typeof config.llm.model !== 'string') {
    throw new Error(`Config ${sourcePath} must define llm.provider and llm.model.`);
  }

  if (!isObject(config.stt) || typeof config.stt.provider !== 'string' || typeof config.stt.model !== 'string') {
    throw new Error(`Config ${sourcePath} must define stt.provider and stt.model.`);
  }

  if (!isObject(config.tts) || typeof config.tts.provider !== 'string' || typeof config.tts.voiceId !== 'string') {
    throw new Error(`Config ${sourcePath} must define tts.provider and tts.voiceId.`);
  }

  if (!Array.isArray(config.tools)) {
    throw new Error(`Config ${sourcePath} must define an array of tools.`);
  }

  config.tools.forEach((tool: any, index: number) => {
    if (!tool || typeof tool.name !== 'string' || !isObject(tool.invoke)) {
      throw new Error(`Tool at index ${index} in ${sourcePath} is missing name or invoke block.`);
    }
  });

  return config as VoiceAgentConfig;
}

function applyLocationOverride(target: VoiceAgentConfig, override: LocationOverride): void {
  deepMerge(target, override);
}

function deepMerge(target: any, override: any): any {
  if (!isObject(override)) {
    return override;
  }

  Object.entries(override).forEach(([key, value]) => {
    const baseValue = (target as any)[key];
    if (Array.isArray(value)) {
      (target as any)[key] = value;
      return;
    }

    if (isObject(value)) {
      (target as any)[key] = isObject(baseValue) ? deepMerge({ ...baseValue }, value) : deepMerge({}, value);
      return;
    }

    (target as any)[key] = value;
  });

  return target;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function deepClone<T>(value: T): T {
  if (typeof globalThis.structuredClone === 'function') {
    return globalThis.structuredClone(value);
  }
  return JSON.parse(JSON.stringify(value));
}
