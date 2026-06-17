import {
  buildReadyEscalationTaskRequest,
  enqueueReadyEscalationTask
} from "../src/ready_escalation_tasks";
import type { NotificationConfig } from "../src/types";

const baseConfig: NotificationConfig = {
  PORT: 8080,
  ENVIRONMENT: "test",
  FIREBASE_PROJECT_ID: "demo-project",
  FIREBASE_SERVICE_ACCOUNT: "{}",
  CLOUD_TASKS_LOCATION: "us-central1",
  CLOUD_TASKS_READY_ESCALATION_QUEUE: "ready-escalation",
  CLOUD_TASKS_OIDC_SERVICE_ACCOUNT_EMAIL: "tasks@example.iam.gserviceaccount.com",
  CLOUD_TASKS_OIDC_AUDIENCE: "https://notification.example.com",
  NOTIFICATION_SERVICE_URL: "https://notification.example.com/"
};

describe("ready escalation Cloud Tasks", () => {
  it("builds a deterministic Cloud Tasks create request", () => {
    const request = buildReadyEscalationTaskRequest(baseConfig, {
      orderId: "order/123",
      storeId: "store-1",
      runAtMs: 1_700_000_000_999
    });

    expect(request.url).toBe(
      "https://cloudtasks.googleapis.com/v2/projects/demo-project/locations/us-central1/queues/ready-escalation/tasks"
    );
    expect(request.data.task.name).toBe(
      "projects/demo-project/locations/us-central1/queues/ready-escalation/tasks/ready-escalation-order_123"
    );
    expect(request.data.task.scheduleTime.seconds).toBe(1_700_000_000);
    expect(request.data.task.httpRequest).toMatchObject({
      httpMethod: "POST",
      url: "https://notification.example.com/tasks/ready-escalation",
      oidcToken: {
        serviceAccountEmail: "tasks@example.iam.gserviceaccount.com",
        audience: "https://notification.example.com"
      }
    });
    expect(Buffer.from(request.data.task.httpRequest.body, "base64").toString("utf8")).toBe(
      JSON.stringify({ orderId: "order/123", storeId: "store-1" })
    );
  });

  it("throws a precise configuration error instead of silently skipping enqueue", () => {
    expect(() =>
      buildReadyEscalationTaskRequest(
        {
          ...baseConfig,
          CLOUD_TASKS_LOCATION: undefined,
          CLOUD_TASKS_READY_ESCALATION_QUEUE: undefined,
          NOTIFICATION_SERVICE_URL: undefined
        },
        { orderId: "order-1", storeId: "store-1", runAtMs: 1_700_000_000_000 }
      )
    ).toThrow(
      "ready escalation Cloud Tasks config missing: CLOUD_TASKS_LOCATION, CLOUD_TASKS_READY_ESCALATION_QUEUE, NOTIFICATION_SERVICE_URL"
    );
  });

  it("creates Cloud Tasks and treats duplicate task names as idempotent", async () => {
    const requestMock = jest
      .fn()
      .mockResolvedValueOnce({})
      .mockRejectedValueOnce({ response: { status: 409 } });
    const auth = {
      getClient: jest.fn(async () => ({ request: requestMock }))
    };

    await expect(
      enqueueReadyEscalationTask(auth, baseConfig, {
        orderId: "order-1",
        storeId: "store-1",
        runAtMs: 1_700_000_000_000
      })
    ).resolves.toBe("created");

    await expect(
      enqueueReadyEscalationTask(auth, baseConfig, {
        orderId: "order-1",
        storeId: "store-1",
        runAtMs: 1_700_000_000_000
      })
    ).resolves.toBe("exists");
    expect(requestMock).toHaveBeenCalledTimes(2);
  });

  it("surfaces non-idempotent Cloud Tasks failures", async () => {
    const auth = {
      getClient: jest.fn(async () => ({
        request: jest.fn(async () => {
          throw new Error("permission denied");
        })
      }))
    };

    await expect(
      enqueueReadyEscalationTask(auth, baseConfig, {
        orderId: "order-1",
        storeId: "store-1",
        runAtMs: 1_700_000_000_000
      })
    ).rejects.toThrow("permission denied");
  });
});
