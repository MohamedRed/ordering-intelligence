import { ChannelContact } from "../types";

type DiscordConfig = {
  DISCORD_BOT_TOKEN?: string;
  DISCORD_API_BASE_URL?: string;
};

type DiscordChannelResponse = {
  id?: string;
};

type DiscordMessageResponse = {
  id?: string;
};

export async function sendDiscordMessage(
  contact: ChannelContact,
  text: string,
  config: DiscordConfig
): Promise<void> {
  const token = config.DISCORD_BOT_TOKEN || process.env.DISCORD_BOT_TOKEN;
  if (!token) {
    throw new Error("missing DISCORD_BOT_TOKEN");
  }
  const userId = contact.userId;
  if (!userId) {
    throw new Error("missing discord userId");
  }

  const apiBase = (config.DISCORD_API_BASE_URL || "https://discord.com/api/v10").replace(/\/+$/, "");
  const channelId = await ensureDmChannel(userId, apiBase, token);
  await sendChannelMessage(channelId, text, apiBase, token);
}

async function ensureDmChannel(userId: string, apiBase: string, token: string): Promise<string> {
  const resp = await fetch(`${apiBase}/users/@me/channels`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bot ${token}`
    },
    body: JSON.stringify({ recipient_id: userId })
  });

  const body = await resp.text();
  if (!resp.ok) {
    throw new Error(`discord dm create failed status=${resp.status} body=${body}`);
  }
  const payload = JSON.parse(body) as DiscordChannelResponse;
  if (!payload.id) {
    throw new Error("discord dm create missing channel id");
  }
  return payload.id;
}

async function sendChannelMessage(
  channelId: string,
  text: string,
  apiBase: string,
  token: string
): Promise<DiscordMessageResponse> {
  const resp = await fetch(`${apiBase}/channels/${channelId}/messages`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bot ${token}`
    },
    body: JSON.stringify({ content: text })
  });

  const body = await resp.text();
  if (!resp.ok) {
    throw new Error(`discord send failed status=${resp.status} body=${body}`);
  }
  return JSON.parse(body) as DiscordMessageResponse;
}
