import type { JobContext, voice } from '@livekit/agents';
import { RoomServiceClient } from 'livekit-server-sdk';

export function registerRoomCleanup(ctx: JobContext, session: voice.AgentSession): void {
  ctx.addShutdownCallback(async () => {
    await safeCloseSession(session);
    await deleteRoom(ctx);
  });
}

async function safeCloseSession(session: voice.AgentSession): Promise<void> {
  try {
    await session.close();
  } catch (error) {
    console.warn('Failed to close agent session cleanly', { error });
  }
}

async function deleteRoom(ctx: JobContext): Promise<void> {
  const roomName = ctx.room?.name;
  if (!roomName) {
    return;
  }

  try {
    const client = resolveRoomServiceClient();
    if (!client) {
      return;
    }

    await client.deleteRoom(roomName);
    console.log('voice-agent-worker:cleanup', { roomName });
  } catch (error) {
    console.warn('Failed to delete LiveKit room during cleanup', { error, roomName });
  }
}

let cachedRoomServiceClient: RoomServiceClient | undefined;

function resolveRoomServiceClient(): RoomServiceClient | undefined {
  if (cachedRoomServiceClient) {
    return cachedRoomServiceClient;
  }

  const url = process.env.LIVEKIT_URL;
  const apiKey = process.env.LIVEKIT_API_KEY;
  const apiSecret = process.env.LIVEKIT_API_SECRET;

  if (!url || !apiKey || !apiSecret) {
    console.warn('Skipping room cleanup because LiveKit credentials are not configured');
    return undefined;
  }

  cachedRoomServiceClient = new RoomServiceClient(url, apiKey, apiSecret);
  return cachedRoomServiceClient;
}

