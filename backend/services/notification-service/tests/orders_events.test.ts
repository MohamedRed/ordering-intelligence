import request from "supertest";

import {
  accessTokenClientRequest,
  eventCallerEmail,
  idTokenClientRequest,
  importNotificationApp,
  twilioMessagesCreate
} from "./support/notification_service_mocks";

describe("/events/orders", () => {
  let app: any;

  beforeEach(async () => {
    app = await importNotificationApp(eventCallerEmail);
  });

  it("acknowledges missing Pub/Sub payload", async () => {
    const res = await request(app)
      .post("/events/orders")
      .set("Authorization", "Bearer event-token")
      .send({});
    expect(res.status).toBe(204);
  });

  it("decodes order event and returns 204", async () => {
    const payload = Buffer.from(
      JSON.stringify({
        id: "order-1",
        storeId: "store-1",
        status: "created",
        customerName: "Test",
        totalCents: 1234
      })
    ).toString("base64");

    const res = await request(app)
      .post("/events/orders")
      .set("Authorization", "Bearer event-token")
      .send({ message: { data: payload } });

    expect(res.status).toBe(204);
  });

  it("sends customer SMS based on store defaults when statusChange is present", async () => {
    (global as any).__firestoreStores.set("store-1", {
      store_id: "store-1",
      twilio_number: "+15550001111",
      order_comms: {
        statuses: {
          ready: { default_channel: "sms" }
        }
      }
    });

    const payload = Buffer.from(
      JSON.stringify({
        id: "order-2",
        storeId: "store-1",
        status: "ready",
        tenantId: "tenant-1",
        callerId: "+15551230000",
        statusChange: {
          previousStatus: "confirmed",
          newStatus: "ready",
          notifyMode: "auto",
          note: "Your order is ready for pickup."
        }
      })
    ).toString("base64");

    const res = await request(app)
      .post("/events/orders")
      .set("Authorization", "Bearer event-token")
      .send({ message: { data: payload } });

    expect(res.status).toBe(204);
    expect(twilioMessagesCreate).toHaveBeenCalledWith(
      expect.objectContaining({
        to: "+15551234567",
        from: "+15550001111",
        body: "Your order is ready for pickup."
      })
    );
    expect(idTokenClientRequest).toHaveBeenCalledWith({
      method: "GET",
      url: "https://customer-profile.example.com/v1/customers/contact?tenantId=tenant-1&callerId=%2B15551230000"
    });
  });

  it("enqueues ready escalation task when enabled", async () => {
    (global as any).__firestoreStores.set("store-1", {
      store_id: "store-1",
      twilio_number: "+15550001111",
      order_comms: {
        ready_escalation_enabled: true,
        ready_escalation_minutes: 1,
        statuses: {
          ready: { default_channel: "none" }
        }
      }
    });

    const payload = Buffer.from(
      JSON.stringify({
        id: "order-3",
        storeId: "store-1",
        status: "ready",
        tenantId: "tenant-1",
        callerId: "+15551230000",
        statusChange: {
          previousStatus: "confirmed",
          newStatus: "ready",
          notifyMode: "none"
        }
      })
    ).toString("base64");

    const res = await request(app)
      .post("/events/orders")
      .set("Authorization", "Bearer event-token")
      .send({ message: { data: payload } });

    expect(res.status).toBe(204);
    expect(accessTokenClientRequest).toHaveBeenCalled();
    const call = (accessTokenClientRequest as any).mock.calls[0]?.[0];
    expect(call).toBeTruthy();
    expect(String(call.url)).toContain("cloudtasks.googleapis.com");
    expect(call.data.task.httpRequest.url).toBe("https://notification-service.example/tasks/ready-escalation");
  });
});
