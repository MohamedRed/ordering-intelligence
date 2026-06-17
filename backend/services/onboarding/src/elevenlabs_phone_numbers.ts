type FetchLike = (url: string, init?: any) => Promise<{
  ok: boolean;
  status: number;
  text: () => Promise<string>;
}>;

type ElevenLabsPhoneNumber =
  | {
      provider: 'twilio';
      phone_number_id: string;
      phone_number: string;
      label?: string;
      assigned_agent?: { agent_id: string } | null;
    }
  | {
      provider: 'sip_trunk';
      phone_number_id: string;
      phone_number: string;
      label?: string;
      assigned_agent?: { agent_id: string } | null;
    };

export type ImportElevenLabsPhoneNumber = (params: {
  phoneNumber: string;
  label: string;
  agentId: string;
}) => Promise<string>;

export function createElevenLabsTemplateAgentResolver(params: {
  fastFoodAgentId: string;
  autoPartsAgentId: string;
  gasStationAgentId: string;
}) {
  return (businessTypeRaw: string): string => {
    const businessType = (businessTypeRaw || '').trim().toLowerCase();
    if (businessType === 'auto_parts') return params.autoPartsAgentId || params.fastFoodAgentId;
    if (businessType === 'gas_station') return params.gasStationAgentId || params.fastFoodAgentId;
    return params.fastFoodAgentId;
  };
}

export function createElevenLabsPhoneNumberImporter(params: {
  apiKey: string;
  apiBaseUrl: string;
  twilioAccountSid: string;
  twilioAuthToken: string;
  fetchImpl: FetchLike;
}): ImportElevenLabsPhoneNumber {
  const elevenlabsJson = async <T>(path: string, opts: { method: string; body?: any }): Promise<T> => {
    if (!params.apiKey) throw new Error('ELEVENLABS_API_KEY not configured');
    const url = `${params.apiBaseUrl}${path}`;
    const res = await params.fetchImpl(url, {
      method: opts.method,
      headers: {
        'Content-Type': 'application/json',
        'xi-api-key': params.apiKey,
      },
      body: opts.body ? JSON.stringify(opts.body) : undefined,
    });
    const text = await res.text();
    if (!res.ok) {
      throw new Error(`elevenlabs ${opts.method} ${path} failed status=${res.status} body=${text.slice(0, 400)}`);
    }
    try {
      return JSON.parse(text) as T;
    } catch {
      throw new Error(`elevenlabs ${opts.method} ${path} invalid json: ${text.slice(0, 200)}`);
    }
  };

  return async ({ phoneNumber, label, agentId }) => {
    let existing: ElevenLabsPhoneNumber | undefined;
    try {
      const list = await elevenlabsJson<ElevenLabsPhoneNumber[]>('/v1/convai/phone-numbers', { method: 'GET' });
      existing = list.find((phone) => phone.phone_number === phoneNumber);
    } catch (err) {
      console.warn('elevenlabs list phone-numbers failed', (err as Error).message);
    }

    const phoneNumberId =
      existing?.phone_number_id ??
      (
        await elevenlabsJson<{ phone_number_id: string }>('/v1/convai/phone-numbers', {
          method: 'POST',
          body: {
            provider: 'twilio',
            phone_number: phoneNumber,
            label,
            sid: params.twilioAccountSid,
            token: params.twilioAuthToken,
            supports_inbound: true,
            supports_outbound: true,
          },
        })
      ).phone_number_id;

    await elevenlabsJson(`/v1/convai/phone-numbers/${encodeURIComponent(phoneNumberId)}`, {
      method: 'PATCH',
      body: { agent_id: agentId },
    });

    return phoneNumberId;
  };
}
