import type { NotificationConfig, StoreDoc } from "./types";

type ElevenLabsConfig = Pick<NotificationConfig, "ELEVENLABS_API_KEY" | "ELEVENLABS_API_BASE_URL">;

export type ElevenLabsOutboundCallParams = {
  store: StoreDoc | null;
  toNumber: string;
  note: string;
  tenantId: string;
  storeId: string;
};

export type ElevenLabsOutboundCallRequest = {
  url: string;
  body: {
    agent_id: string;
    agent_phone_number_id: string;
    to_number: string;
    conversation_initiation_client_data: {
      dynamic_variables: {
        tenantId: string;
        storeId: string;
        note: string;
      };
    };
  };
  headers: {
    "xi-api-key": string;
    "Content-Type": "application/json";
  };
  timeout: number;
};

type HttpClient = {
  post: (
    url: string,
    data?: ElevenLabsOutboundCallRequest["body"],
    config?: Pick<ElevenLabsOutboundCallRequest, "headers" | "timeout">
  ) => Promise<unknown>;
};

export function buildElevenLabsOutboundCallRequest(
  config: ElevenLabsConfig,
  params: ElevenLabsOutboundCallParams
): ElevenLabsOutboundCallRequest {
  const apiKey = String(config.ELEVENLABS_API_KEY ?? "").trim();
  if (!apiKey) {
    throw new Error("elevenlabs api key not configured for outbound call");
  }

  const base = String(config.ELEVENLABS_API_BASE_URL ?? "https://api.elevenlabs.io").replace(/\/+$/, "");
  const agentId =
    String(params.store?.elevenlabs_agent_id ?? "").trim() ||
    String(params.store?.elevenlabs_agent_template_id ?? "").trim();
  const phoneNumberId = String(params.store?.elevenlabs_phone_number_id ?? "").trim();
  const missing = [
    ["elevenlabs_agent_id or elevenlabs_agent_template_id", agentId],
    ["elevenlabs_phone_number_id", phoneNumberId]
  ]
    .filter(([, value]) => !value)
    .map(([name]) => name);

  if (missing.length > 0) {
    throw new Error(`elevenlabs store config missing for outbound call: ${missing.join(", ")}`);
  }

  return {
    url: `${base}/v1/convai/twilio/outbound-call`,
    body: {
      agent_id: agentId,
      agent_phone_number_id: phoneNumberId,
      to_number: params.toNumber,
      conversation_initiation_client_data: {
        dynamic_variables: {
          tenantId: params.tenantId,
          storeId: params.storeId,
          note: params.note
        }
      }
    },
    headers: {
      "xi-api-key": apiKey,
      "Content-Type": "application/json"
    },
    timeout: 15_000
  };
}

export async function startElevenLabsOutboundCall(
  httpClient: HttpClient,
  config: ElevenLabsConfig,
  params: ElevenLabsOutboundCallParams,
  dryRun: boolean
): Promise<"started" | "dry_run"> {
  if (dryRun) {
    console.log(
      JSON.stringify({
        level: "info",
        event: "elevenlabs_outbound_call_dry_run",
        to: params.toNumber,
        storeId: params.storeId
      })
    );
    return "dry_run";
  }

  const request = buildElevenLabsOutboundCallRequest(config, params);
  await httpClient.post(request.url, request.body, {
    headers: request.headers,
    timeout: request.timeout
  });
  console.log(
    JSON.stringify({
      level: "info",
      event: "elevenlabs_outbound_call_started",
      to: params.toNumber,
      storeId: params.storeId
    })
  );
  return "started";
}
