import {
  maskPhone,
  normalizePhoneNumberKey,
  phoneRouteDocIdFromElevenLabsPhoneNumberId,
  phoneRouteDocIdFromToNumber,
} from './phone_routes';

describe('phone route helpers', () => {
  it('normalizes formatted phone numbers while preserving a leading plus', () => {
    expect(normalizePhoneNumberKey(' +1 (555) 123-4567 ')).toBe('+15551234567');
  });

  it('builds stable route document IDs from destination numbers', () => {
    expect(phoneRouteDocIdFromToNumber('+1 (555) 123-4567')).toBe('to_15551234567');
  });

  it('builds stable route document IDs from ElevenLabs phone number IDs', () => {
    expect(phoneRouteDocIdFromElevenLabsPhoneNumberId(' elpn_123 ')).toBe('elpn_elpn_123');
  });

  it('masks long phone numbers and leaves short values readable', () => {
    expect(maskPhone('+15551234567')).toBe('+15...567');
    expect(maskPhone('123456')).toBe('123456');
    expect(maskPhone(undefined)).toBe('');
  });
});
