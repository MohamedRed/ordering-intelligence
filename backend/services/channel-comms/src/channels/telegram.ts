import { ChannelContact } from "../types";

type TelegramConfig = {
  TELEGRAM_BOT_TOKEN?: string;
  TELEGRAM_API_BASE_URL?: string;
};

export async function sendTelegramMessage(
  contact: ChannelContact,
  text: string,
  config: TelegramConfig
): Promise<void> {
  const token = config.TELEGRAM_BOT_TOKEN || process.env.TELEGRAM_BOT_TOKEN;
  if (!token) {
    throw new Error("missing TELEGRAM_BOT_TOKEN");
  }

  const chatId = contact.userId;
  if (!chatId) {
    throw new Error("missing telegram userId");
  }

  const apiBase = (config.TELEGRAM_API_BASE_URL || "https://api.telegram.org").replace(/\/+$/, "");
  const payload: Record<string, unknown> = {
    chat_id: chatId,
    text
  };
  if (contact.threadId) {
    const threadIdNum = Number(contact.threadId);
    if (!Number.isNaN(threadIdNum)) {
      payload.message_thread_id = threadIdNum;
    }
  }

  const resp = await fetch(`${apiBase}/bot${token}/sendMessage`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });

  if (!resp.ok) {
    const body = await resp.text();
    throw new Error(`telegram send failed status=${resp.status} body=${body}`);
  }
}
