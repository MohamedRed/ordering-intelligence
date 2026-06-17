import { Buffer } from "buffer";

import type { PubSubPushEnvelope } from "./types";

export type PubSubDecodeFailureReason = "missing_data" | "invalid_json";

export type PubSubDecodeResult<T> =
  | {
      ok: true;
      value: T;
      messageId?: string;
      subscription?: string;
    }
  | {
      ok: false;
      reason: PubSubDecodeFailureReason;
      messageId?: string;
      subscription?: string;
      error?: Error;
    };

export function decodePubSubJson<T>(body: PubSubPushEnvelope | null | undefined): PubSubDecodeResult<T> {
  const message = body?.message;
  const messageId = typeof message?.messageId === "string" ? message.messageId : undefined;
  const subscription = typeof body?.subscription === "string" ? body.subscription : undefined;
  const data = typeof message?.data === "string" ? message.data.trim() : "";

  if (!data) {
    return { ok: false, reason: "missing_data", messageId, subscription };
  }

  try {
    const value = JSON.parse(Buffer.from(data, "base64").toString("utf8")) as T;
    return { ok: true, value, messageId, subscription };
  } catch (err) {
    return {
      ok: false,
      reason: "invalid_json",
      messageId,
      subscription,
      error: err instanceof Error ? err : undefined
    };
  }
}

export function logPubSubDecodeFailure<T>(endpoint: string, result: PubSubDecodeResult<T>): void {
  if (result.ok) {
    return;
  }

  const context = {
    endpoint,
    reason: result.reason,
    messageId: result.messageId,
    subscription: result.subscription
  };

  if (result.error) {
    console.warn("Skipping malformed Pub/Sub push message", context, result.error);
    return;
  }

  console.warn("Skipping malformed Pub/Sub push message", context);
}
