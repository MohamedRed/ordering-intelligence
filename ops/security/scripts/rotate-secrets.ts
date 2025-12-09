#!/usr/bin/env ts-node
import { SecretManagerServiceClient } from '@google-cloud/secret-manager';
import dotenv from 'dotenv';
import { existsSync } from 'node:fs';
import path from 'node:path';

const rootDir = path.resolve(process.cwd(), '..', '..');
const envPath = path.join(rootDir, 'infra', 'secrets', '.env');

if (!existsSync(envPath)) {
  console.error(`Unable to locate shared secret file at ${envPath}`);
  process.exit(1);
}

dotenv.config({ path: envPath });

type EnvironmentKey = 'dev' | 'staging' | 'prod';

const PROJECTS: Record<EnvironmentKey, string> = {
  dev: 'ordering-intelligence',
  staging: 'ordering-intelligence-staging',
  prod: 'ordering-intelligence-prod',
};

const SECRET_MAP: Record<string, string> = {
  TWILIO_AUTH_TOKEN: 'twilio-auth-token',
  LIVEKIT_API_KEY: 'livekit-api-key',
  LIVEKIT_API_SECRET: 'livekit-api-secret',
};

const DRY_RUN = process.argv.includes('--dry-run');

function getSecretValue(envKey: EnvironmentKey, varName: string): string | undefined {
  const suffix = envKey.toUpperCase();
  return (
    process.env[`${varName}_${suffix}`] ??
    process.env[varName] ??
    undefined
  );
}

async function main() {
  const client = new SecretManagerServiceClient();

  for (const [envKey, projectId] of Object.entries(PROJECTS) as [EnvironmentKey, string][]) {
    console.log(`\n[${envKey}] rotating secrets in project ${projectId}`);

    for (const [envVar, secretId] of Object.entries(SECRET_MAP)) {
      const value = getSecretValue(envKey, envVar);
      if (!value) {
        console.warn(`  - ${envVar}: skipped (no value found)`);
        continue;
      }

      if (DRY_RUN) {
        console.log(`  - ${envVar}: DRY RUN (would add new version to ${secretId})`);
        continue;
      }

      const parent = `projects/${projectId}/secrets/${secretId}`;
      await client.addSecretVersion({
        parent,
        payload: {
          data: Buffer.from(value, 'utf8'),
        },
      });

      console.log(`  - ${envVar}: added new version to ${secretId}`);
    }
  }

  console.log('\nSecret rotation complete.');
}

main().catch((err) => {
  console.error('Rotation script failed:', err);
  process.exit(1);
});
