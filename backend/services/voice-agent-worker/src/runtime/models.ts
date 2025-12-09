import { inference, voice } from '@livekit/agents';
import type { LoadedVoiceAgentConfig } from '@ordering-intelligence/voice-agent-config';

import { createToolContext, ToolContextOptions } from './tools';
import { OrderState } from './order-state';
import type { MenuSnapshot } from './menu';

export interface PreparedModels {
  stt: inference.STT<any>;
  llm: inference.LLM;
  tts: inference.TTS<any>;
}

export function createPreparedModels(config: LoadedVoiceAgentConfig): PreparedModels {
  return {
    stt: createStt(config),
    llm: createLlm(config),
    tts: createTts(config),
  };
}

export function createAgentSession(models: PreparedModels): voice.AgentSession {
  return new voice.AgentSession({
    turnDetection: 'stt',
    stt: models.stt,
    llm: models.llm,
    tts: models.tts,
    // Allow the model to chain multiple tool calls per user turn (useful for rapid cleanup/edits).
    voiceOptions: {
      maxToolSteps: 10,
    },
  });
}

export function createVoiceAgent(
  config: LoadedVoiceAgentConfig,
  models: PreparedModels,
  orderState: OrderState,
  toolOptions?: ToolContextOptions,
  menu?: MenuSnapshot,
): voice.Agent {
  return new voice.Agent({
    instructions: config.llm.systemPrompt,
    tools: createToolContext(config.tools, orderState, toolOptions, menu),
    stt: models.stt,
    llm: models.llm,
    tts: models.tts,
  });
}

function createLlm(config: LoadedVoiceAgentConfig): inference.LLM {
  const descriptor = `${config.llm.provider}/${config.llm.model}`;
  return new inference.LLM({
    model: descriptor,
    modelOptions: {
      temperature: config.llm.temperature ?? 0.3,
    },
  });
}

function createStt(config: LoadedVoiceAgentConfig): inference.STT<any> {
  const base = `${config.stt.provider}/${config.stt.model}`;
  const descriptor = config.stt.language ? `${base}:${config.stt.language}` : base;
  return inference.STT.fromModelString(descriptor);
}

function createTts(config: LoadedVoiceAgentConfig): inference.TTS<any> {
  const model = resolveTtsModel(config);
  return new inference.TTS({
    model,
    voice: config.tts.voiceId,
    language: config.tts.language,
  });
}

function resolveTtsModel(config: LoadedVoiceAgentConfig): string {
  if (config.tts.model && config.tts.model.includes('/')) {
    return config.tts.model;
  }

  const defaultModels: Record<string, string> = {
    elevenlabs: 'elevenlabs/eleven_turbo_v2',
    cartesia: 'cartesia/sonic-2',
  };

  if (config.tts.model) {
    return `${config.tts.provider}/${config.tts.model}`;
  }

  return defaultModels[config.tts.provider] ?? config.tts.provider;
}
