import { GoogleAuth } from "google-auth-library";
import { OrderRecord } from "./models";

export async function submitGroupOrder(orderServiceUrl: string, groupOrderId: string) {
  const auth = new GoogleAuth();
  const client = await auth.getIdTokenClient(orderServiceUrl);
  const url = `${orderServiceUrl.replace(/\/$/, "")}/group_orders/${encodeURIComponent(groupOrderId)}/submit`;
  const res = await client.request({ url, method: "POST", data: {} });
  return res.data;
}

export async function fetchOrder(orderServiceUrl: string, orderId: string): Promise<OrderRecord | null> {
  const auth = new GoogleAuth();
  const client = await auth.getIdTokenClient(orderServiceUrl);
  const url = `${orderServiceUrl.replace(/\/$/, "")}/orders/${encodeURIComponent(orderId)}`;
  try {
    const res = await client.request({ url, method: "GET" });
    const data = res.data as Record<string, unknown>;
    const fuel = (data.fuel as Record<string, unknown> | undefined) ?? undefined;
    return {
      id: String(data.id || orderId),
      tenantId: String(data.tenantId || ""),
      storeId: data.storeId ? String(data.storeId) : undefined,
      customerId: data.customerId ? String(data.customerId) : undefined,
      customerName: data.customerName ? String(data.customerName) : undefined,
      paymentMethod: data.paymentMethod ? String(data.paymentMethod) : undefined,
      totalCents: Number(data.totalCents || 0),
      fuelPaymentFlow: fuel?.paymentFlow ? String(fuel.paymentFlow) : undefined
    };
  } catch (err: any) {
    if (err?.response?.status === 404) {
      return null;
    }
    throw err;
  }
}

export async function updateOrderStatus(orderServiceUrl: string, orderId: string, status: string) {
  const auth = new GoogleAuth();
  const client = await auth.getIdTokenClient(orderServiceUrl);
  const url = `${orderServiceUrl.replace(/\/$/, "")}/orders/${encodeURIComponent(orderId)}/status`;
  const res = await client.request({ url, method: "PATCH", data: { status } });
  return res.data;
}
