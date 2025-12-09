export type VoiceAgentEnvironment = 'dev' | 'staging' | 'prod';

export interface LlmConfig {
  provider: string;
  model: string;
  systemPrompt: string;
  temperature?: number;
  [key: string]: unknown;
}

export interface SttConfig {
  provider: string;
  model: string;
  language?: string;
  [key: string]: unknown;
}

export interface TtsConfig {
  provider: string;
  model?: string;
  voiceId: string;
  language?: string;
  gender?: string;
  style?: string;
  [key: string]: unknown;
}

export interface VadConfig {
  mode?: string;
  silenceTimeoutMs?: number;
  maxSilenceMs?: number;
  [key: string]: unknown;
}

export interface ToolInvokeConfig {
  method: string;
  url: string;
  headers?: Record<string, string>;
  [key: string]: unknown;
}

export interface ToolConfig {
  name: string;
  description?: string;
  invoke: ToolInvokeConfig;
  [key: string]: unknown;
}

export interface SafetyConfig {
  lowConfidenceEscalation?: {
    enabled: boolean;
    threshold?: number;
    maxConsecutiveTurns?: number;
    [key: string]: unknown;
  };
  confirmationPolicy?: {
    requireExplicitConfirm?: boolean;
    confirmationTemplate?: string;
    [key: string]: unknown;
  };
  blockedTopics?: string[];
  [key: string]: unknown;
}

export interface VoiceAgentConfig {
  presetName: string;
  description?: string;
  llm: LlmConfig;
  stt: SttConfig;
  tts: TtsConfig;
  vad?: VadConfig;
  tools: ToolConfig[];
  safety?: SafetyConfig;
  locationOverrides?: Record<string, LocationOverride>;
  [key: string]: unknown;
}

export type LocationOverride = Partial<Omit<VoiceAgentConfig, 'presetName' | 'description' | 'locationOverrides'>>;

export interface LoadVoiceAgentOptions {
  env?: VoiceAgentEnvironment;
  baseDir?: string;
  locationCode?: string;
  overrides?: Partial<Omit<VoiceAgentConfig, 'locationOverrides'>>;
  fallbackLocationCode?: string;
}

export interface LoadedVoiceAgentConfig extends VoiceAgentConfig {
  environment: VoiceAgentEnvironment;
  sourcePath: string;
  appliedLocationCode?: string;
}

export type TelephonyProvider = 'us-livekit-pstn' | 'sip-trunk';

export interface TelephonyRoutingConfig {
  provider: TelephonyProvider;
  number: string;
  dispatchRuleId: string;
}
