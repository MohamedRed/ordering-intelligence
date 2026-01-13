import { GroupOrderAllocation, GroupOrderSession } from "../models";

export const DEFAULT_CURRENCY = "usd";

export function allocationForParticipant(
  allocations: GroupOrderAllocation[] | undefined,
  participantId: string
) {
  if (!allocations) return undefined;
  return allocations.find((alloc) => alloc.participantId === participantId);
}

export function resolvePayerId(groupOrder: GroupOrderSession, participantId?: string) {
  const mode = (groupOrder.paymentMode || "single_payer").toLowerCase();
  if (mode === "split_by_participant") {
    return String(participantId || "").trim();
  }
  return groupOrder.participants?.[0]?.participantId || "";
}
