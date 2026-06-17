import type { Firestore } from "@google-cloud/firestore";

import {
  DELIVERY_COMMS_RATE_LIMIT_DEFAULT,
  safeDocId,
  toMillis
} from "./comms_helpers";
import type { StoreDeliveryComms } from "./types";

export type ShouldSendDeliveryCommsParams = {
  storeId: string;
  orderId?: string;
  eventKey: string;
  comms?: StoreDeliveryComms | null;
  eventVersion?: string;
};

export async function shouldSendDeliveryComms(
  firestore: Firestore,
  params: ShouldSendDeliveryCommsParams
): Promise<boolean> {
  const orderId = String(params.orderId ?? "").trim();
  const eventKey = String(params.eventKey ?? "").trim();
  if (!orderId || !eventKey) return true;

  const eventVersion = String(params.eventVersion ?? "v1").trim() || "v1";
  const storeRef = firestore.collection("stores").doc(params.storeId);
  const eventDocId = safeDocId(`${orderId}_${eventKey}_${eventVersion}`);
  const eventRef = storeRef.collection("delivery_comms_events").doc(eventDocId);
  const stateRef = storeRef.collection("delivery_comms_state").doc(orderId);
  const limitRaw = Number(params.comms?.rate_limit_per_hour ?? DELIVERY_COMMS_RATE_LIMIT_DEFAULT);
  const rateLimit = Number.isFinite(limitRaw) ? limitRaw : DELIVERY_COMMS_RATE_LIMIT_DEFAULT;
  const windowMs = 60 * 60 * 1000;
  const now = Date.now();

  try {
    return await firestore.runTransaction(async (tx) => {
      const [eventSnap, stateSnap] = await Promise.all([tx.get(eventRef), tx.get(stateRef)]);
      if (eventSnap.exists) return false;

      let count = 0;
      let windowStart = now;
      if (stateSnap.exists) {
        const data = stateSnap.data() ?? {};
        const lastStart = toMillis((data as any).windowStart ?? (data as any).window_start);
        const lastCount = Number((data as any).count ?? 0);
        if (lastStart > 0 && now - lastStart < windowMs) {
          count = Number.isFinite(lastCount) ? lastCount : 0;
          windowStart = lastStart;
        }
      }

      if (rateLimit > 0 && count >= rateLimit) {
        return false;
      }

      tx.create(eventRef, {
        storeId: params.storeId,
        orderId,
        eventKey,
        eventVersion,
        createdAt: new Date(now)
      });
      tx.set(
        stateRef,
        {
          orderId,
          count: count + 1,
          windowStart: new Date(windowStart),
          updatedAt: new Date(now)
        },
        { merge: true }
      );
      return true;
    });
  } catch (err) {
    console.warn(JSON.stringify({
      level: "warn",
      event: "delivery_comms_guardrails_failed",
      orderId,
      eventKey,
      message: (err as Error).message
    }));
    return false;
  }
}
