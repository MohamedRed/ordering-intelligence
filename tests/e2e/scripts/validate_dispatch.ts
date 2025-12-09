import 'dotenv/config';

import type { SIPDispatchRuleInfo, SIPInboundTrunkInfo } from '@livekit/protocol';
import { SipClient } from 'livekit-server-sdk';
import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';

type Options = {
  runCall: boolean;
  waitUntilAnswered: boolean;
  callTimeout: number;
  logDetails: boolean;
  providerOverride?: 'us-livekit-pstn' | 'sip-trunk';
};

const argv = yargs(hideBin(process.argv))
  .option('run-call', {
    type: 'boolean',
    default: parseBooleanEnv('LIVEKIT_SIP_HEALTH_RUN_CALL', false),
    description: 'Place a synthetic SIP call via the outbound trunk after validating config.'
  })
  .option('wait-until-answered', {
    type: 'boolean',
    default: parseBooleanEnv('LIVEKIT_SIP_HEALTH_WAIT_UNTIL_ANSWERED', true),
    description: 'Block until the synthetic call is answered (requires voicemail or auto-answer).'
  })
  .option('call-timeout', {
    type: 'number',
    default: Number.parseInt(process.env.LIVEKIT_SIP_HEALTH_TIMEOUT ?? '60000', 10),
    description: 'Maximum time in milliseconds to wait for the synthetic call before failing.'
  })
  .option('log-details', {
    type: 'boolean',
    default: true,
    description: 'Print trunk/dispatch metadata after validation.'
  })
  .option('provider', {
    type: 'string',
    choices: ['us-livekit-pstn', 'sip-trunk'],
    description: 'Override TELEPHONY_PROVIDER when selecting health-call target (US LiveKit number vs carrier DID).'
  })
  .strict()
  .help()
  .parseSync() as Options;

function parseBooleanEnv(name: string, fallback: boolean): boolean {
  const value = process.env[name];
  if (value === undefined) {
    return fallback;
  }
  return ['1', 'true', 'yes'].includes(value.toLowerCase());
}

function getEnv(name: string, options: { required?: boolean; fallback?: string } = {}): string | undefined {
  const value = process.env[name] ?? options.fallback;
  if ((value === undefined || value === '') && options.required) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function parseCsvEnv(name: string): string[] {
  const value = process.env[name];
  if (!value) {
    return [];
  }
  return value
    .split(',')
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);
}

async function validateInboundTrunk(
  client: SipClient,
  trunkId: string,
  expectedNumbers: string[],
  logDetails: boolean
): Promise<SIPInboundTrunkInfo> {
  const [trunk] = await client.listSipInboundTrunk({ trunkIds: [trunkId] });
  if (!trunk) {
    throw new Error(`LiveKit inbound trunk ${trunkId} was not found.`);
  }

  const numbers = trunk.numbers ?? [];
  if (expectedNumbers.length > 0) {
    const missing = expectedNumbers.filter((number) => !numbers.includes(number));
    if (missing.length > 0) {
      throw new Error(`Inbound trunk ${trunkId} is missing expected numbers: ${missing.join(', ')}`);
    }
  }

  if (logDetails) {
    console.log('[livekit] Inbound trunk validated:');
    console.log(`  id: ${trunkId}`);
    console.log(`  name: ${trunk.name}`);
    console.log(`  numbers: ${numbers.join(', ') || '(none)'}`);
    if (trunk.allowedNumbers?.length) {
      console.log(`  allowedNumbers: ${trunk.allowedNumbers.join(', ')}`);
    }
    if (trunk.allowedAddresses?.length) {
      console.log(`  allowedAddresses: ${trunk.allowedAddresses.join(', ')}`);
    }
  }

  return trunk;
}

async function validateDispatchRule(
  client: SipClient,
  dispatchRuleId: string,
  trunkId: string | undefined,
  expectedPin: string | undefined,
  logDetails: boolean
): Promise<SIPDispatchRuleInfo> {
  const [rule] = await client.listSipDispatchRule({ dispatchRuleIds: [dispatchRuleId] });
  if (!rule) {
    throw new Error(`Dispatch rule ${dispatchRuleId} was not found.`);
  }

  if (trunkId && rule.trunkIds?.length && !rule.trunkIds.includes(trunkId)) {
    throw new Error(`Dispatch rule ${dispatchRuleId} is not linked to inbound trunk ${trunkId}.`);
  }

  const dispatchUnion = rule.rule?.rule;

  if (expectedPin && dispatchUnion?.case === 'dispatchRuleDirect') {
    const configuredPin = dispatchUnion.value.pin ?? '';
    if (configuredPin !== expectedPin) {
      throw new Error(
        `Dispatch rule ${dispatchRuleId} pin mismatch. Expected ${expectedPin}, found ${configuredPin || '(none)'}.`
      );
    }
  }

  if (logDetails) {
    console.log('[livekit] Dispatch rule validated:');
    console.log(`  id: ${dispatchRuleId}`);
    console.log(`  name: ${rule.name}`);
    if (rule.trunkIds?.length) {
      console.log(`  trunkIds: ${rule.trunkIds.join(', ')}`);
    }
    if (dispatchUnion?.case === 'dispatchRuleIndividual') {
      console.log(`  individual roomPrefix: ${dispatchUnion.value.roomPrefix}`);
    }
    if (dispatchUnion?.case === 'dispatchRuleDirect') {
      console.log(`  direct roomName: ${dispatchUnion.value.roomName}`);
    }
    if (dispatchUnion?.case === 'dispatchRuleCallee') {
      console.log(`  callee roomPrefix: ${dispatchUnion.value.roomPrefix}`);
    }
    if (rule.attributes) {
      console.log(`  attributes: ${JSON.stringify(rule.attributes)}`);
    }
  }

  return rule;
}

async function runHealthCall(client: SipClient, options: Options): Promise<void> {
  const outboundTrunkId = getEnv('LIVEKIT_SIP_OUTBOUND_TRUNK_ID', { required: true })!;
  const provider = (options.providerOverride ??
    (process.env.TELEPHONY_PROVIDER as 'us-livekit-pstn' | 'sip-trunk' | undefined)) ?? 'sip-trunk';

  const callTo =
    provider === 'us-livekit-pstn'
      ? getEnv('TELEPHONY_NUMBER', { required: true })!
      : getEnv('LIVEKIT_SIP_HEALTH_CALL_TO', { required: true })!;

  const roomName =
    getEnv('LIVEKIT_SIP_HEALTH_ROOM', { fallback: `sip-health-${new Date().toISOString().slice(0, 10)}` })!;
  const identityPrefix = getEnv('LIVEKIT_SIP_HEALTH_IDENTITY_PREFIX', { fallback: 'sip-health' })!;
  const participantIdentity = `${identityPrefix}-${Date.now()}`;
  const participantName = getEnv('LIVEKIT_SIP_HEALTH_PARTICIPANT_NAME', { fallback: 'SIP Health Check' })!;
  const dtmf = getEnv('LIVEKIT_SIP_HEALTH_DTMF');
  const attributes = parseKeyValueEnv('LIVEKIT_SIP_HEALTH_ATTRIBUTES');

  console.log('[health-call] Initiating synthetic call via LiveKit SIP outbound trunk...');
  const participant = await client.createSipParticipant(outboundTrunkId, callTo, roomName, {
    participantIdentity,
    participantName,
    participantAttributes: { ...attributes, 'health-check': 'true' },
    dtmf,
    waitUntilAnswered: options.waitUntilAnswered,
    timeout: Math.ceil(options.callTimeout / 1000),
    playDialtone: true,
    krispEnabled: true
  });

  console.log('[health-call] Call created:');
  console.log(`  room: ${participant.roomName}`);
  console.log(`  participantIdentity: ${participant.participantIdentity}`);
  console.log(`  participantId: ${participant.participantId}`);
  console.log(`  sipCallId: ${participant.sipCallId}`);
}

function parseKeyValueEnv(name: string): Record<string, string> {
  const value = process.env[name];
  if (!value) {
    return {};
  }
  return value.split(',').reduce<Record<string, string>>((acc, pair) => {
    const [key, rawValue] = pair.split('=').map((entry) => entry.trim());
    if (key && rawValue) {
      acc[key] = rawValue;
    }
    return acc;
  }, {});
}

async function main(): Promise<void> {
  const livekitUrl = getEnv('LIVEKIT_URL', { required: true })!;
  const livekitKey = getEnv('LIVEKIT_API_KEY', { required: true })!;
  const livekitSecret = getEnv('LIVEKIT_API_SECRET', { required: true })!;
  const inboundTrunkId = getEnv('LIVEKIT_SIP_INBOUND_TRUNK_ID');
  const dispatchRuleId = getEnv('LIVEKIT_SIP_DISPATCH_RULE_ID');
  const expectedNumbers = parseCsvEnv('LIVEKIT_SIP_EXPECTED_NUMBERS');
  const expectedPin = getEnv('LIVEKIT_SIP_EXPECTED_PIN');

  const client = new SipClient(livekitUrl, livekitKey, livekitSecret);

  if (inboundTrunkId) {
    await validateInboundTrunk(client, inboundTrunkId, expectedNumbers, argv.logDetails);
  } else {
    console.warn('[livekit] LIVEKIT_SIP_INBOUND_TRUNK_ID not set; skipping trunk validation.');
  }

  if (dispatchRuleId) {
    await validateDispatchRule(client, dispatchRuleId, inboundTrunkId, expectedPin, argv.logDetails);
  } else {
    console.warn('[livekit] LIVEKIT_SIP_DISPATCH_RULE_ID not set; skipping dispatch validation.');
  }

  if (argv.runCall) {
    await runHealthCall(client, argv);
  } else {
    console.log('[health-call] Skipped (run-call=false).');
  }
}

main().catch((error) => {
  console.error('[livekit] SIP validation failed:', error);
  process.exitCode = 1;
});
