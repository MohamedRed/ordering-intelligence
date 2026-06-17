import { Timestamp, type CollectionReference } from '@google-cloud/firestore';
import {
  normalizePhoneNumberKey,
  phoneRouteDocIdFromElevenLabsPhoneNumberId,
  phoneRouteDocIdFromToNumber,
} from './phone_routes.js';

export type UpsertPhoneNumberRouteParams = {
  onboardingSessionId: string;
  toNumber?: string;
  elevenlabsPhoneNumberId?: string;
  twilioSid?: string;
  tenantId?: string;
  storeId?: string;
  businessType?: string;
  routeStatus?: string;
  source: 'onboarding_voice_number' | 'onboarding_finalize' | 'manual';
};

export function createPhoneNumberRouteStore(phoneNumberRoutes: CollectionReference) {
  return async function upsertPhoneNumberRoute(params: UpsertPhoneNumberRouteParams): Promise<void> {
    const ts = Timestamp.now();
    const onboardingSessionId = params.onboardingSessionId.trim();
    const toNumber = params.toNumber ? normalizePhoneNumberKey(params.toNumber) : '';
    const elevenlabsPhoneNumberId = (params.elevenlabsPhoneNumberId || '').trim();

    const tenantId = (params.tenantId || '').trim() || `tenant_${onboardingSessionId}`;
    const storeId = (params.storeId || '').trim() || `store_${onboardingSessionId}`;

    const payload: any = {
      route_version: 1,
      source: params.source,
      route_status: params.routeStatus || 'active',
      onboarding_session_id: onboardingSessionId,
      tenant_id: tenantId,
      store_id: storeId,
      business_type: (params.businessType || '').trim(),
      ...(toNumber ? { to_number: toNumber } : {}),
      ...(params.twilioSid ? { twilio_sid: String(params.twilioSid).trim() } : {}),
      ...(elevenlabsPhoneNumberId ? { elevenlabs_phone_number_id: elevenlabsPhoneNumberId } : {}),
      updated_at: ts,
      created_at: ts,
    };

    const writes: Promise<any>[] = [];
    if (toNumber) {
      writes.push(phoneNumberRoutes.doc(phoneRouteDocIdFromToNumber(toNumber)).set(payload, { merge: true }));
    }
    if (elevenlabsPhoneNumberId) {
      writes.push(
        phoneNumberRoutes.doc(phoneRouteDocIdFromElevenLabsPhoneNumberId(elevenlabsPhoneNumberId)).set(payload, {
          merge: true,
        }),
      );
    }
    if (!writes.length) return;
    await Promise.all(writes);
  };
}
