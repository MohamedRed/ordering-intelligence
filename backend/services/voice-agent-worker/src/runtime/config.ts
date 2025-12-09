import type { JobContext } from '@livekit/agents';
import {
  inferVoiceAgentEnvironment,
  loadVoiceAgentConfig,
  loadTelephonyRouting,
  type LoadedVoiceAgentConfig,
  type TelephonyRoutingConfig,
} from '@ordering-intelligence/voice-agent-config';

import { defaultConfigDir, resolveAgentName } from '../constants';
import { extractJobData } from './job-data';

export interface RuntimeContext {
  environment: string;
  locationCode?: string;
  configDir: string;
  agentName: string;
  voiceAgentConfig: LoadedVoiceAgentConfig;
  telephonyRouting: TelephonyRoutingConfig;
}

export function buildRuntimeContext(ctx: JobContext): RuntimeContext {
  const jobData = extractJobData(ctx);
  const envSource: NodeJS.ProcessEnv = { ...process.env };

  if (jobData?.environment) {
    envSource.APP_ENV = jobData.environment;
  }

  const environment = inferVoiceAgentEnvironment(envSource);
  const configDir = process.env.VOICE_AGENT_CONFIG_DIR ?? defaultConfigDir;
  const locationCode = jobData?.voiceProfile?.location_code ?? process.env.VOICE_AGENT_LOCATION_CODE;

  const voiceAgentConfig = loadVoiceAgentConfig({
    env: environment,
    baseDir: configDir,
    locationCode,
  });

  const telephonyRouting = loadTelephonyRouting(envSource);

  return {
    environment: voiceAgentConfig.environment,
    locationCode: voiceAgentConfig.appliedLocationCode ?? locationCode,
    configDir,
    agentName: resolveAgentName(),
    voiceAgentConfig,
    telephonyRouting,
  };
}
