import request from "supertest";

import {
  axiosPost,
  importNotificationApp,
  tasksCallerEmail
} from "./support/notification_service_mocks";

describe("/tasks/ready-escalation", () => {
  let app: any;

  beforeEach(async () => {
    app = await importNotificationApp(tasksCallerEmail);
  });

  it("starts outbound call when order still ready and store escalation enabled", async () => {
    (global as any).__firestoreOrders.set("order-4", {
      id: "order-4",
      storeId: "store-1",
      status: "ready",
      tenantId: "tenant-1",
      callerId: "+15551230000"
    });
    (global as any).__firestoreStores.set("store-1", {
      store_id: "store-1",
      elevenlabs_agent_template_id: "agent_123",
      elevenlabs_phone_number_id: "pn_123",
      order_comms: {
        ready_escalation_enabled: true,
        ready_escalation_channel: "call"
      }
    });

    const res = await request(app)
      .post("/tasks/ready-escalation")
      .set("Authorization", "Bearer task-token")
      .send({ orderId: "order-4", storeId: "store-1" });

    expect(res.status).toBe(204);
    expect(axiosPost).toHaveBeenCalledWith(
      "https://api.elevenlabs.io/v1/convai/twilio/outbound-call",
      expect.objectContaining({
        agent_id: "agent_123",
        agent_phone_number_id: "pn_123",
        to_number: "+15551234567"
      }),
      expect.any(Object)
    );
  });
});
