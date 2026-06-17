import type { StoreOrderComms, StoreOrderCommsTemplate } from "./types";

export const DELIVERY_COMMS_RATE_LIMIT_DEFAULT = 3;

export function resolveTemplateFromComms(
  status: string,
  comms?: StoreOrderComms | null,
  templateId?: string
): StoreOrderCommsTemplate | null {
  const statuses = comms?.statuses ?? {};
  const cfg = statuses[status] ?? statuses[String(status).toLowerCase()] ?? undefined;
  const templates = cfg?.templates ?? [];
  const explicit = String(templateId ?? "").trim();
  if (explicit) {
    const hit = templates.find((template) => String(template?.id ?? "").trim() === explicit);
    if (hit) return hit;
  }
  const def = String(cfg?.default_template_id ?? "").trim();
  if (def) {
    const hit = templates.find((template) => String(template?.id ?? "").trim() === def);
    if (hit) return hit;
  }
  return null;
}

export function defaultMessageForStatus(status: string): string {
  switch (status) {
    case "confirmed":
      return "Your order has been confirmed.";
    case "ready":
      return "Your order is ready for pickup.";
    case "delivery_assigned":
      return "Your delivery is being prepared. A driver has been assigned.";
    case "picked_up":
      return "Your order has been picked up and is on the way.";
    case "out_for_delivery":
      return "Your order is out for delivery.";
    case "arriving_soon":
      return "Your driver is nearby. Arriving soon.";
    case "delivered":
      return "Delivered. Enjoy!";
    case "delivery_failed":
      return "We couldn't complete the delivery. Please contact the store.";
    case "completed":
      return "Thanks — your order is marked completed.";
    case "cancelled":
      return "Your order was cancelled. Please contact the store if you have questions.";
    case "delay":
      return "Your order is running a bit late.";
    case "pending":
    default:
      return "Your order status was updated.";
  }
}

export function normalizeDeliveryEvent(kind: string, status: string): string {
  const raw = String(kind || status || "").trim().toLowerCase();
  if (!raw) return "";
  if (raw === "delivery_dispatched" || raw === "dispatched" || raw === "assigned" || raw === "delivery_assigned") {
    return "delivery_assigned";
  }
  if (raw === "picked_up" || raw === "pickup_complete" || raw === "pickup") return "picked_up";
  if (raw === "out_for_delivery" || raw === "en_route" || raw === "enroute" || raw === "in_transit") {
    return "out_for_delivery";
  }
  if (raw === "arriving_soon" || raw === "approaching") return "arriving_soon";
  if (raw === "delivered" || raw === "delivery_completed") return "delivered";
  if (raw === "cancelled" || raw === "canceled" || raw === "failed" || raw === "delivery_failed") {
    return "delivery_failed";
  }
  return "";
}

export function normalizeDispatchEvent(kind: string): string {
  const raw = kind.trim().toLowerCase();
  if (raw === "driver_assigned") return "delivery_assigned";
  if (raw === "out_for_delivery" || raw === "en_route" || raw === "enroute") return "out_for_delivery";
  if (raw === "delivered") return "delivered";
  if (raw === "delivery_failed" || raw === "failed" || raw === "assignment_expired") return "delivery_failed";
  return "";
}

export function safeDocId(value: string): string {
  return value.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 240);
}

export function toMillis(value: any): number {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "number") return value;
  if (typeof value === "string") {
    const ms = Date.parse(value);
    return Number.isFinite(ms) ? ms : 0;
  }
  return 0;
}
