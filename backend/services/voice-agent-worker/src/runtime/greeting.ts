import type { voice } from '@livekit/agents';
import type { LoadedVoiceAgentConfig } from '@ordering-intelligence/voice-agent-config';

export function enqueueGreeting(
  session: voice.AgentSession,
  config: LoadedVoiceAgentConfig,
): void {
  const fallback =
    'Bonjour, je suis votre assistant de commande. Dites-moi ce que vous souhaitez et je m’en occupe !';
  const message = config.description ?? fallback;

  try {
    session.say(message, { allowInterruptions: true, addToChatCtx: false });
  } catch (error) {
    console.warn('Failed to enqueue greeting', { error });
  }
}

