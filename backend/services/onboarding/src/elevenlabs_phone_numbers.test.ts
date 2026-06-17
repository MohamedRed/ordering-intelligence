import {
  createElevenLabsPhoneNumberImporter,
  createElevenLabsTemplateAgentResolver,
} from './elevenlabs_phone_numbers';

function makeResponse(status: number, body: unknown) {
  return {
    ok: status >= 200 && status < 300,
    status,
    text: async () => (typeof body === 'string' ? body : JSON.stringify(body)),
  };
}

describe('ElevenLabs phone number helpers', () => {
  it('resolves business-specific template agents with fast-food fallback', () => {
    const resolve = createElevenLabsTemplateAgentResolver({
      fastFoodAgentId: 'fast',
      autoPartsAgentId: '',
      gasStationAgentId: 'gas',
    });

    expect(resolve('auto_parts')).toBe('fast');
    expect(resolve('gas_station')).toBe('gas');
    expect(resolve('unknown')).toBe('fast');
  });

  it('reuses an existing phone number and assigns the selected agent', async () => {
    const fetchImpl = jest
      .fn()
      .mockResolvedValueOnce(makeResponse(200, [{ phone_number_id: 'elpn_existing', phone_number: '+15551230000' }]))
      .mockResolvedValueOnce(makeResponse(200, { ok: true }));
    const importer = createElevenLabsPhoneNumberImporter({
      apiKey: 'key',
      apiBaseUrl: 'https://eleven.test',
      twilioAccountSid: 'AC123',
      twilioAuthToken: 'token',
      fetchImpl,
    });

    const id = await importer({ phoneNumber: '+15551230000', label: 'Demo', agentId: 'agent-1' });

    expect(id).toBe('elpn_existing');
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(fetchImpl.mock.calls[1]).toEqual([
      'https://eleven.test/v1/convai/phone-numbers/elpn_existing',
      expect.objectContaining({ method: 'PATCH', body: JSON.stringify({ agent_id: 'agent-1' }) }),
    ]);
  });

  it('creates a missing phone number before assigning the selected agent', async () => {
    const fetchImpl = jest
      .fn()
      .mockResolvedValueOnce(makeResponse(200, []))
      .mockResolvedValueOnce(makeResponse(200, { phone_number_id: 'elpn_created' }))
      .mockResolvedValueOnce(makeResponse(200, { ok: true }));
    const importer = createElevenLabsPhoneNumberImporter({
      apiKey: 'key',
      apiBaseUrl: 'https://eleven.test',
      twilioAccountSid: 'AC123',
      twilioAuthToken: 'token',
      fetchImpl,
    });

    const id = await importer({ phoneNumber: '+15551230000', label: 'Demo', agentId: 'agent-1' });

    expect(id).toBe('elpn_created');
    expect(JSON.parse(fetchImpl.mock.calls[1][1].body)).toMatchObject({
      provider: 'twilio',
      phone_number: '+15551230000',
      label: 'Demo',
      sid: 'AC123',
      token: 'token',
      supports_inbound: true,
      supports_outbound: true,
    });
  });

  it('surfaces non-JSON responses as API errors', async () => {
    const importer = createElevenLabsPhoneNumberImporter({
      apiKey: 'key',
      apiBaseUrl: 'https://eleven.test',
      twilioAccountSid: 'AC123',
      twilioAuthToken: 'token',
      fetchImpl: jest.fn(async () => makeResponse(200, 'not-json')),
    });

    await expect(importer({ phoneNumber: '+15551230000', label: 'Demo', agentId: 'agent-1' })).rejects.toThrow(
      'invalid json',
    );
  });
});
