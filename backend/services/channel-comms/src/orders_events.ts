import { Request, Response } from "express";
import { ChannelContact } from "./types";
import { sendDiscordMessage } from "./channels/discord";
import { sendTelegramMessage } from "./channels/telegram";
import { ChannelCommsConfig } from "./config";

type PubSubPushEnvelope = { message?: { data?: string } };
type OrderStatusChange = { previousStatus?: string; newStatus?: string; note?: string };
type OrderEvent = {
  id?: string;
  displayNumber?: string;
  storeId?: string;
  status?: string;
  channel?: string;
  customerName?: string;
  statusChange?: OrderStatusChange;
  channelContact?: ChannelContact;
};
type OrdersEventEnvelope = { kind?: string; order?: OrderEvent } | OrderEvent;

export async function handleOrdersEvent(req: Request, res: Response, config: ChannelCommsConfig) {
  const payload = decodeOrdersEvent(req.body);
  const order = extractOrder(payload);
  if (!order) {
    res.status(200).json({ status: "ignored" });
    return;
  }
  if (!order.statusChange?.newStatus) {
    res.status(200).json({ status: "no_status_change" });
    return;
  }
  const contact = order.channelContact;
  if (!contact || !contact.channel) {
    res.status(200).json({ status: "no_channel_contact" });
    return;
  }
  const channel = normalizeChannel(contact.channel);
  const message = buildOrderUpdateMessage(order, order.statusChange?.newStatus || "updated");
  try {
    if (channel === "telegram") {
      await sendTelegramMessage({ ...contact, channel }, message, config);
    } else if (channel === "discord") {
      await sendDiscordMessage({ ...contact, channel }, message, config);
    } else {
      console.log(JSON.stringify({ level: "info", event: "channel_comms_unsupported", channel }));
    }
  } catch (err) {
    console.error(JSON.stringify({ level: "error", event: "channel_comms_failed", message: (err as Error).message }));
  }
  res.status(200).json({ status: "ok" });
}

function decodeOrdersEvent(body: unknown): OrdersEventEnvelope | null {
  if (!body) return null;
  const asEnvelope = body as PubSubPushEnvelope;
  if (asEnvelope.message?.data) {
    try {
      const decoded = Buffer.from(asEnvelope.message.data, "base64").toString("utf8");
      return JSON.parse(decoded) as OrdersEventEnvelope;
    } catch {
      return null;
    }
  }
  return body as OrdersEventEnvelope;
}

function extractOrder(payload: OrdersEventEnvelope | null): OrderEvent | null {
  if (!payload) return null;
  if ((payload as any).order) return (payload as any).order as OrderEvent;
  return payload as OrderEvent;
}

function normalizeChannel(channel: string): string {
  const value = channel.trim().toLowerCase();
  if (value === "telegram_webapp" || value === "telegram") return "telegram";
  if (value === "discord_webapp" || value === "discord") return "discord";
  return value;
}

function buildOrderUpdateMessage(order: OrderEvent, status: string): string {
  const displayNumber = String(order.displayNumber ?? (order as any).display_number ?? "").trim();
  const orderId = displayNumber ? `Order #${displayNumber}` : order.id ? `Order ${order.id}` : "Your order";
  const customer = order.customerName ? `, ${order.customerName}` : "";
  const note = order.statusChange?.note ? `\nNote: ${order.statusChange.note}` : "";
  return `${orderId}${customer} is now ${status}.${note}`;
}
