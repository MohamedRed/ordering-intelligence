import type { NotificationConfig } from "./types";

type ReadyEscalationConfig = Pick<
  NotificationConfig,
  | "FIREBASE_PROJECT_ID"
  | "CLOUD_TASKS_PROJECT_ID"
  | "CLOUD_TASKS_LOCATION"
  | "CLOUD_TASKS_READY_ESCALATION_QUEUE"
  | "CLOUD_TASKS_OIDC_SERVICE_ACCOUNT_EMAIL"
  | "CLOUD_TASKS_OIDC_AUDIENCE"
  | "NOTIFICATION_SERVICE_URL"
>;

type GoogleAuthLike = {
  getClient: () => Promise<{
    request: (params: CloudTaskCreateRequest) => Promise<unknown>;
  }>;
};

export type ReadyEscalationTaskParams = {
  orderId: string;
  storeId: string;
  runAtMs: number;
};

export type CloudTaskCreateRequest = {
  url: string;
  method: "POST";
  data: {
    task: {
      name: string;
      scheduleTime: { seconds: number };
      httpRequest: {
        httpMethod: "POST";
        url: string;
        headers: { "Content-Type": "application/json" };
        oidcToken: { serviceAccountEmail: string; audience: string };
        body: string;
      };
    };
  };
};

type ResolvedReadyEscalationConfig = {
  projectId: string;
  location: string;
  queue: string;
  targetBaseUrl: string;
  oidcServiceAccountEmail: string;
  oidcAudience: string;
};

export function buildReadyEscalationTaskRequest(
  config: ReadyEscalationConfig,
  params: ReadyEscalationTaskParams
): CloudTaskCreateRequest {
  const resolved = resolveReadyEscalationConfig(config);
  const runAtSeconds = Math.max(0, Math.floor(params.runAtMs / 1000));
  const safeOrderId = params.orderId.replace(/[^A-Za-z0-9_-]/g, "_");
  const taskName = `projects/${resolved.projectId}/locations/${resolved.location}/queues/${resolved.queue}/tasks/ready-escalation-${safeOrderId}`;
  const bodyJson = JSON.stringify({ orderId: params.orderId, storeId: params.storeId });

  return {
    url: `https://cloudtasks.googleapis.com/v2/projects/${encodeURIComponent(resolved.projectId)}/locations/${encodeURIComponent(resolved.location)}/queues/${encodeURIComponent(resolved.queue)}/tasks`,
    method: "POST",
    data: {
      task: {
        name: taskName,
        scheduleTime: { seconds: runAtSeconds },
        httpRequest: {
          httpMethod: "POST",
          url: `${resolved.targetBaseUrl}/tasks/ready-escalation`,
          headers: { "Content-Type": "application/json" },
          oidcToken: {
            serviceAccountEmail: resolved.oidcServiceAccountEmail,
            audience: resolved.oidcAudience
          },
          body: Buffer.from(bodyJson, "utf8").toString("base64")
        }
      }
    }
  };
}

export async function enqueueReadyEscalationTask(
  auth: GoogleAuthLike,
  config: ReadyEscalationConfig,
  params: ReadyEscalationTaskParams
): Promise<"created" | "exists"> {
  const request = buildReadyEscalationTaskRequest(config, params);
  const client = await auth.getClient();
  try {
    await client.request(request);
    return "created";
  } catch (err: any) {
    if (err?.response?.status === 409) {
      return "exists";
    }
    throw err;
  }
}

function resolveReadyEscalationConfig(config: ReadyEscalationConfig): ResolvedReadyEscalationConfig {
  const projectId = String(config.CLOUD_TASKS_PROJECT_ID ?? config.FIREBASE_PROJECT_ID ?? "").trim();
  const location = String(config.CLOUD_TASKS_LOCATION ?? "").trim();
  const queue = String(config.CLOUD_TASKS_READY_ESCALATION_QUEUE ?? "").trim();
  const targetBaseUrl = String(config.NOTIFICATION_SERVICE_URL ?? "").trim().replace(/\/+$/, "");
  const oidcServiceAccountEmail = String(config.CLOUD_TASKS_OIDC_SERVICE_ACCOUNT_EMAIL ?? "").trim();
  const oidcAudience = String(config.CLOUD_TASKS_OIDC_AUDIENCE ?? targetBaseUrl).trim();

  const missing = [
    ["CLOUD_TASKS_PROJECT_ID or FIREBASE_PROJECT_ID", projectId],
    ["CLOUD_TASKS_LOCATION", location],
    ["CLOUD_TASKS_READY_ESCALATION_QUEUE", queue],
    ["NOTIFICATION_SERVICE_URL", targetBaseUrl],
    ["CLOUD_TASKS_OIDC_SERVICE_ACCOUNT_EMAIL", oidcServiceAccountEmail],
    ["CLOUD_TASKS_OIDC_AUDIENCE or NOTIFICATION_SERVICE_URL", oidcAudience]
  ]
    .filter(([, value]) => !value)
    .map(([name]) => name);

  if (missing.length > 0) {
    throw new Error(`ready escalation Cloud Tasks config missing: ${missing.join(", ")}`);
  }

  return {
    projectId,
    location,
    queue,
    targetBaseUrl,
    oidcServiceAccountEmail,
    oidcAudience
  };
}
