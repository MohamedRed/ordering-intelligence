import type { JobContext } from '@livekit/agents';
import { ServerOptions, defineAgent } from '@livekit/agents';
import { DataPacket_Kind, RoomServiceClient } from 'livekit-server-sdk';

import { resolveAgentName } from '../constants';
import { buildRuntimeContext } from './config';
import { enqueueGreeting } from './greeting';
import { registerRoomCleanup } from './hangup';
import { createAgentSession, createPreparedModels, createVoiceAgent } from './models';
import { OrderState } from './order-state';
import { fetchMenuSnapshot, formatMenuInstructions, type MenuSnapshot } from './menu';
import { maybeStartMenuUpdateListener } from './menu-updates';

const AGENT_NAME = resolveAgentName();

defineAgent({
  entry: async (ctx: JobContext) => {
    const runtime = buildRuntimeContext(ctx);
    const orderServiceUrl = resolveOrderServiceUrl(runtime.environment);
    const configuredStoreId =
      typeof runtime.voiceAgentConfig.storeId === 'string' ? runtime.voiceAgentConfig.storeId : undefined;
    const menuSnapshot = await maybeStartMenuUpdateListener(orderServiceUrl, configuredStoreId) ??
      await fetchMenuSnapshot(orderServiceUrl, configuredStoreId);

    await ctx.connect();
    const participant = await ctx.waitForParticipant();

    const orderState = new OrderState();

    const location = runtime.voiceAgentConfig.appliedLocationCode ?? runtime.locationCode ?? 'default';
    console.log('voice-agent-worker:start', {
      participant: participant.identity,
      environment: runtime.environment,
      location,
      preset: runtime.voiceAgentConfig.presetName,
      telephonyProvider: runtime.telephonyRouting.provider,
      telephonyNumber: runtime.telephonyRouting.number,
    });

    const agentPrompt = buildInstructions(runtime.voiceAgentConfig.llm.systemPrompt, menuSnapshot);
    const agentConfig = {
      ...runtime.voiceAgentConfig,
      llm: { ...runtime.voiceAgentConfig.llm, systemPrompt: agentPrompt },
    };

    const models = createPreparedModels(agentConfig);
    const session = createAgentSession(models);

    const agent = createVoiceAgent(agentConfig, models, orderState, {
      onCompleteOrder: async ({ totalPrice, items }) => {
        await broadcastCheckout(ctx, totalPrice, items.length);
      },
    }, menuSnapshot);

    await session.start({
      agent,
      room: ctx.room,
      inputOptions: { audioEnabled: true, textEnabled: true },
      outputOptions: { audioEnabled: true, transcriptionEnabled: true },
    });

    registerRpcHandlers(ctx, orderState);
    enqueueGreeting(session, runtime.voiceAgentConfig);
    registerRoomCleanup(ctx, session);
  },
});

export function createWorkerOptions(agentPath: string): ServerOptions {
  return new ServerOptions({
    agent: agentPath,
    agentName: AGENT_NAME,
  });
}

function buildInstructions(systemPrompt: string, menuSnapshot: MenuSnapshot | undefined): string {
  const menuText = formatMenuInstructions(menuSnapshot);
  if (!menuText) return systemPrompt;
  return `${systemPrompt}\n\n${menuText}`;
}

function registerRpcHandlers(ctx: JobContext, orderState: OrderState): void {
  const room = ctx.room;
  if (!room?.localParticipant) {
    return;
  }

  room.localParticipant.registerRpcMethod('get_order_state', async () => {
    const items = orderState.list();
    const totalPrice = orderState.total();
    return JSON.stringify({
      success: true,
      data: { items, total_price: totalPrice, item_count: items.length },
    });
  });
}

async function broadcastCheckout(ctx: JobContext, totalPrice: number, itemCount: number): Promise<void> {
  const roomName = ctx.room?.name;
  if (!roomName) return;

  try {
    const client = resolveRoomServiceClient();
    if (!client) return;

    const payload = Buffer.from(
      JSON.stringify({
        type: 'show_checkout',
        total_price: totalPrice,
        item_count: itemCount,
        message: `Your total is ${totalPrice.toFixed(2)}.`,
      }),
    );

    await client.sendData(roomName, payload, DataPacket_Kind.RELIABLE, {});
    console.log('voice-agent-worker:checkout_rpc', { roomName, totalPrice, itemCount });
  } catch (error) {
    console.warn('Failed to broadcast checkout payload', { error, roomName, totalPrice });
  }
}

let cachedRoomServiceClient: RoomServiceClient | undefined;

function resolveRoomServiceClient(): RoomServiceClient | undefined {
  if (cachedRoomServiceClient) return cachedRoomServiceClient;

  const url = process.env.LIVEKIT_URL;
  const apiKey = process.env.LIVEKIT_API_KEY;
  const apiSecret = process.env.LIVEKIT_API_SECRET;

  if (!url || !apiKey || !apiSecret) {
    console.warn('Skipping checkout broadcast because LiveKit credentials are not configured');
    return undefined;
  }

  cachedRoomServiceClient = new RoomServiceClient(url, apiKey, apiSecret);
  return cachedRoomServiceClient;
}

function resolveOrderServiceUrl(environment: string): string | undefined {
  // Prefer explicit env-specific variables, fall back to ORDER_SERVICE_URL.
  const envKey = environment === 'prod' ? 'PROD_ORDER_SERVICE_URL' : environment === 'staging' ? 'STAGING_ORDER_SERVICE_URL' : 'ORDER_SERVICE_URL';
  const specific = process.env[envKey];
  if (specific) return specific;
  return process.env.ORDER_SERVICE_URL;
}
