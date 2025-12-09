import type { JobContext } from '@livekit/agents';

export interface AgentJobData {
  environment?: string;
  voiceProfile?: {
    location_code?: string;
  };
}

export function extractJobData(ctx: JobContext): AgentJobData | undefined {
  const metadata = ctx.job?.metadata?.trim();
  if (metadata) {
    try {
      return JSON.parse(metadata) as AgentJobData;
    } catch (error) {
      console.warn('Unable to parse job metadata for AgentJobData', { error, metadata });
    }
  }

  const legacyData = (ctx as JobContext & { data?: unknown }).data;
  if (legacyData && typeof legacyData === 'object') {
    return legacyData as AgentJobData;
  }

  return undefined;
}

