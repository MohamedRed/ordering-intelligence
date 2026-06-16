export function maskPhone(phone: string | undefined): string {
  if (!phone) return '';
  const clean = String(phone);
  if (clean.length <= 6) return clean;
  return `${clean.slice(0, 3)}...${clean.slice(-3)}`;
}

export function normalizePhoneNumberKey(phone: string | undefined): string {
  if (!phone) return '';
  return String(phone).trim().replace(/[^\d+]/g, '');
}

export function phoneRouteDocIdFromToNumber(toNumber: string): string {
  const normalized = normalizePhoneNumberKey(toNumber);
  const withoutPlus = normalized.startsWith('+') ? normalized.slice(1) : normalized;
  return `to_${withoutPlus}`;
}

export function phoneRouteDocIdFromElevenLabsPhoneNumberId(id: string): string {
  return `elpn_${String(id).trim()}`;
}
