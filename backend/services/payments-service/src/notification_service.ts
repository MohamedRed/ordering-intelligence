import { GoogleAuth } from "google-auth-library";
import { ChannelContact } from "./models";

type NotificationPayload = {
  title: string;
  body: string;
  data?: Record<string, string>;
};

type NotifyRequest = {
  channel: Array<"sms" | "email">;
  target: { phoneNumber?: string; email?: string };
  payload: NotificationPayload;
};

const phoneKeys = ["phoneNumber", "phone", "phone_number", "sms"];
const emailKeys = ["email", "emailAddress", "email_address"];

function metadataValue(contact: ChannelContact | undefined, keys: string[]): string {
  const meta = contact?.metadata ?? {};
  for (const key of keys) {
    const value = meta[key];
    if (typeof value === "string" && value.trim() !== "") {
      return value.trim();
    }
  }
  return "";
}

function inferTarget(contact?: ChannelContact): NotifyRequest | null {
  if (!contact) return null;
  const channel = (contact.channel || "").toLowerCase();
  let phone = metadataValue(contact, phoneKeys);
  let email = metadataValue(contact, emailKeys);
  if (!phone && ["sms", "whatsapp", "phone"].includes(channel)) {
    phone = (contact.userId || "").trim();
  }
  if (!email && channel === "email") {
    email = (contact.userId || "").trim();
  }
  const channels: Array<"sms" | "email"> = [];
  if (phone) channels.push("sms");
  if (email) channels.push("email");
  if (channels.length === 0) return null;
  return { channel: channels, target: { phoneNumber: phone || undefined, email: email || undefined }, payload: { title: "", body: "" } };
}

export async function sendGroupOrderNotification(
  notificationServiceUrl: string | undefined,
  contact: ChannelContact | undefined,
  payload: NotificationPayload
) {
  if (!notificationServiceUrl) return;
  const base = notificationServiceUrl.replace(/\/+$/, "");
  const request = inferTarget(contact);
  if (!request) return;
  request.payload = payload;
  const auth = new GoogleAuth();
  const client = await auth.getIdTokenClient(base);
  await client.request({
    url: `${base}/group-orders/notify`,
    method: "POST",
    data: request
  });
}
