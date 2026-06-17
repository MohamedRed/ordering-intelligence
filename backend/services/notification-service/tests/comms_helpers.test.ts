import {
  defaultMessageForStatus,
  normalizeDeliveryEvent,
  normalizeDispatchEvent,
  resolveTemplateFromComms,
  safeDocId,
  toMillis
} from "../src/comms_helpers";

describe("notification comms helpers", () => {
  it("resolves explicit and default templates from store comms config", () => {
    const comms = {
      statuses: {
        ready: {
          default_template_id: "default",
          templates: [
            { id: "default", body: "Default ready" },
            { id: "custom", body: "Custom ready" }
          ]
        }
      }
    };

    expect(resolveTemplateFromComms("ready", comms, "custom")?.body).toBe("Custom ready");
    expect(resolveTemplateFromComms("READY", { statuses: { READY: comms.statuses.ready } })?.body).toBe(
      "Default ready"
    );
    expect(resolveTemplateFromComms("missing", comms)).toBeNull();
  });

  it("maps order and delivery status defaults to customer-facing copy", () => {
    expect(defaultMessageForStatus("ready")).toBe("Your order is ready for pickup.");
    expect(defaultMessageForStatus("delivery_failed")).toBe(
      "We couldn't complete the delivery. Please contact the store."
    );
    expect(defaultMessageForStatus("unknown")).toBe("Your order status was updated.");
  });

  it("normalizes delivery-service and dispatch-service event names", () => {
    expect(normalizeDeliveryEvent("delivery_dispatched", "")).toBe("delivery_assigned");
    expect(normalizeDeliveryEvent("", "en_route")).toBe("out_for_delivery");
    expect(normalizeDeliveryEvent("delivery_completed", "")).toBe("delivered");
    expect(normalizeDeliveryEvent("failed", "")).toBe("delivery_failed");
    expect(normalizeDeliveryEvent("unknown", "")).toBe("");

    expect(normalizeDispatchEvent("driver_assigned")).toBe("delivery_assigned");
    expect(normalizeDispatchEvent("enroute")).toBe("out_for_delivery");
    expect(normalizeDispatchEvent("assignment_expired")).toBe("delivery_failed");
    expect(normalizeDispatchEvent("marketplace_offer")).toBe("");
  });

  it("builds Firestore-safe document ids and normalizes timestamp-like values", () => {
    expect(safeDocId("order:1/status ready")).toBe("order_1_status_ready");
    expect(safeDocId("x".repeat(300))).toHaveLength(240);

    const date = new Date("2026-01-01T00:00:00Z");
    expect(toMillis(date)).toBe(date.getTime());
    expect(toMillis(date.toISOString())).toBe(date.getTime());
    expect(toMillis({ toMillis: () => 123 })).toBe(123);
    expect(toMillis("not-a-date")).toBe(0);
  });
});
