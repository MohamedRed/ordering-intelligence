import type { NotificationConfig } from "./types";

type CustomerContactConfig = Pick<NotificationConfig, "CUSTOMER_PROFILE_SERVICE_URL">;

type GoogleAuthLike = {
  getIdTokenClient: (audience: string) => Promise<{
    request: (params: { url: string; method: "GET" }) => Promise<{ data?: unknown }>;
  }>;
};

export type CustomerContactLookupParams = {
  tenantId: string;
  callerId: string;
};

export type CustomerContact = {
  phoneE164?: string;
  customerName?: string;
};

type RawCustomerContact = {
  phoneE164?: unknown;
  customerName?: unknown;
};

export async function resolveCustomerContact(
  googleAuth: GoogleAuthLike,
  config: CustomerContactConfig,
  params: CustomerContactLookupParams
): Promise<CustomerContact | null> {
  const tenantId = params.tenantId.trim();
  const callerId = params.callerId.trim();
  if (!callerId) return null;

  const base = String(config.CUSTOMER_PROFILE_SERVICE_URL ?? "").trim().replace(/\/+$/, "");
  if (!base || !tenantId) {
    return { phoneE164: callerId, customerName: "" };
  }

  const data = await fetchCustomerContact(googleAuth, base, tenantId, callerId);
  return {
    phoneE164: String(data.phoneE164 ?? "").trim(),
    customerName: String(data.customerName ?? "").trim()
  };
}

async function fetchCustomerContact(
  googleAuth: GoogleAuthLike,
  base: string,
  tenantId: string,
  callerId: string
): Promise<RawCustomerContact> {
  const url = `${base}/v1/customers/contact?tenantId=${encodeURIComponent(tenantId)}&callerId=${encodeURIComponent(callerId)}`;
  const client = await googleAuth.getIdTokenClient(base);
  const resp = await client.request({ url, method: "GET" });
  return (resp.data ?? {}) as RawCustomerContact;
}
