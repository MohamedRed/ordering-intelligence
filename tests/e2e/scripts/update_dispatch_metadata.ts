import 'dotenv/config';

import fs from 'node:fs/promises';

import { SipClient } from 'livekit-server-sdk';
import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';

type Options = {
  dispatchRuleId: string;
  environment?: string;
  locationCode?: string;
  metadataJson?: string;
  metadataPath?: string;
  dryRun: boolean;
  pretty: boolean;
};

const envSuffix = () => {
  const derived = process.env.APP_ENV ?? process.env.ENVIRONMENT;
  return derived ? derived.toUpperCase() : undefined;
};

const envSpecific = (key: string): string | undefined => {
  const suffix = envSuffix();
  if (!suffix) {
    return undefined;
  }
  return process.env[`${key}_${suffix}`];
};

const argv = yargs(hideBin(process.argv))
  .option('dispatch-rule-id', {
    type: 'string',
    description: 'Target LiveKit SIP dispatch rule ID',
    default: process.env.LIVEKIT_SIP_DISPATCH_RULE_ID ?? envSpecific('LIVEKIT_SIP_DISPATCH_RULE_ID'),
    demandOption: true,
  })
  .option('environment', {
    type: 'string',
    description: 'Environment label to embed in the metadata (dev/staging/prod)',
    default: process.env.APP_ENV ?? process.env.ENVIRONMENT,
  })
  .option('location-code', {
    type: 'string',
    description: 'voice_profile.location_code value to set',
  })
  .option('metadata-json', {
    type: 'string',
    description: 'Additional metadata (JSON string) to shallow-merge into the dispatch metadata',
  })
  .option('metadata-path', {
    type: 'string',
    description: 'Path to a JSON file to merge into the metadata payload',
  })
  .option('dry-run', {
    type: 'boolean',
    default: false,
    description: 'Print the merged metadata without updating LiveKit',
  })
  .option('pretty', {
    type: 'boolean',
    default: true,
    description: 'Pretty-print the metadata payload before updating',
  })
  .strict()
  .help()
  .parseSync() as Options;

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable ${name}`);
  }
  return value;
}

function parseMetadata(raw: string | undefined, label: string): Record<string, unknown> {
  if (!raw?.trim()) {
    return {};
  }
  try {
    return JSON.parse(raw);
  } catch (err) {
    throw new Error(`Unable to parse ${label} JSON: ${(err as Error).message}`);
  }
}

async function readMetadataFile(path?: string): Promise<Record<string, unknown>> {
  if (!path) {
    return {};
  }
  const content = await fs.readFile(path, 'utf8');
  return parseMetadata(content, `metadata file ${path}`);
}

function mergeMetadata(base: Record<string, any>, extra: Record<string, any>): Record<string, any> {
  const output = { ...base };
  for (const [key, value] of Object.entries(extra)) {
    if (
      value &&
      typeof value === 'object' &&
      !Array.isArray(value) &&
      typeof output[key] === 'object' &&
      !Array.isArray(output[key])
    ) {
      output[key] = mergeMetadata(output[key] as Record<string, any>, value as Record<string, any>);
    } else {
      output[key] = value;
    }
  }
  return output;
}

(async () => {
  const livekitUrl = requireEnv('LIVEKIT_URL');
  const livekitKey = requireEnv('LIVEKIT_API_KEY');
  const livekitSecret = requireEnv('LIVEKIT_API_SECRET');
  const client = new SipClient(livekitUrl, livekitKey, livekitSecret);

  const dispatchRuleId = argv.dispatchRuleId;
  const [rule] = await client.listSipDispatchRule({ dispatchRuleIds: [dispatchRuleId] });
  if (!rule) {
    throw new Error(`Dispatch rule ${dispatchRuleId} was not found`);
  }

  let mergedMetadata: Record<string, any> = {};
  let existingNormalized: string | undefined;
  if (rule.metadata) {
    try {
      mergedMetadata = JSON.parse(rule.metadata);
      existingNormalized = JSON.stringify(mergedMetadata);
    } catch (err) {
      console.warn('[metadata] Existing metadata is not valid JSON, starting fresh.', err);
      mergedMetadata = {};
    }
  }

  if (argv.environment) {
    mergedMetadata.environment = argv.environment;
  }
  if (argv.locationCode) {
    mergedMetadata.voiceProfile = {
      ...(mergedMetadata.voiceProfile ?? {}),
      location_code: argv.locationCode,
    };
  }

  mergedMetadata = mergeMetadata(mergedMetadata, parseMetadata(argv.metadataJson, '--metadata-json'));
  mergedMetadata = mergeMetadata(mergedMetadata, await readMetadataFile(argv.metadataPath));

  const normalizedNew = JSON.stringify(mergedMetadata);
  const metadataString = argv.pretty ? JSON.stringify(mergedMetadata, null, 2) : normalizedNew;

  console.log(`[metadata] Dispatch rule: ${dispatchRuleId}`);
  console.log('[metadata] Payload to apply:');
  console.log(metadataString);

  if (argv.dryRun) {
    console.log('[metadata] Dry run enabled, skipping LiveKit update.');
    return;
  }

  if (existingNormalized && existingNormalized === normalizedNew) {
    console.log('[metadata] No changes detected, skipping LiveKit update.');
    return;
  }

  await client.updateSipDispatchRuleFields(dispatchRuleId, {
    metadata: metadataString,
  });

  console.log('[metadata] Dispatch rule metadata updated successfully.');
})();
