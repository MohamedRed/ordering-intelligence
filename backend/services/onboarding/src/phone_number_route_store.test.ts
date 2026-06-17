import { createPhoneNumberRouteStore } from './phone_number_route_store';

function makeCollection() {
  const writes: Array<{ id: string; payload: any; options?: any }> = [];
  return {
    writes,
    collection: {
      doc: (id: string) => ({
        set: async (payload: any, options?: any) => {
          writes.push({ id, payload, options });
        },
      }),
    },
  };
}

describe('phone number route store', () => {
  it('writes stable route documents for Twilio and ElevenLabs identifiers', async () => {
    const { collection, writes } = makeCollection();
    const upsert = createPhoneNumberRouteStore(collection as any);

    await upsert({
      onboardingSessionId: ' session-1 ',
      toNumber: '+1 (555) 123-0000',
      elevenlabsPhoneNumberId: ' elpn_123 ',
      twilioSid: ' PN123 ',
      tenantId: ' tenant-1 ',
      storeId: ' store-1 ',
      businessType: ' fast_food ',
      routeStatus: 'ready',
      source: 'onboarding_finalize',
    });

    expect(writes).toHaveLength(2);
    expect(writes.map((write) => write.id)).toEqual(['to_15551230000', 'elpn_elpn_123']);
    expect(writes[0].payload).toMatchObject({
      route_version: 1,
      source: 'onboarding_finalize',
      route_status: 'ready',
      onboarding_session_id: 'session-1',
      tenant_id: 'tenant-1',
      store_id: 'store-1',
      business_type: 'fast_food',
      to_number: '+15551230000',
      twilio_sid: 'PN123',
      elevenlabs_phone_number_id: 'elpn_123',
    });
    expect(writes[0].options).toEqual({ merge: true });
  });

  it('skips writes when no routable phone identifier is present', async () => {
    const { collection, writes } = makeCollection();
    const upsert = createPhoneNumberRouteStore(collection as any);

    await upsert({ onboardingSessionId: 'session-1', source: 'manual' });

    expect(writes).toEqual([]);
  });
});
