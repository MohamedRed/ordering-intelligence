import path from 'node:path';
import { fileURLToPath } from 'node:url';

const currentDir = path.dirname(fileURLToPath(import.meta.url));

export const repoRoot = path.resolve(currentDir, '..', '..', '..', '..');
export const defaultConfigDir = path.resolve(repoRoot, 'infra', 'voice-agents');

const FALLBACK_AGENT_NAME = 'oi-voice-agent';

export function resolveAgentName(): string {
  const candidate = process.env.VOICE_AGENT_NAME?.trim();
  return candidate && candidate.length > 0 ? candidate : FALLBACK_AGENT_NAME;
}

