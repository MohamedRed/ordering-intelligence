import 'dotenv/config';

import { Firestore } from '@google-cloud/firestore';
import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';

type Options = {
  projectId?: string;
  collection: string;
  documentId?: string;
  docPath?: string;
  locationCode: string;
  presetId?: string;
  locale?: string;
  dryRun: boolean;
};

const argv = yargs(hideBin(process.argv))
  .option('project-id', {
    type: 'string',
    description: 'Firestore project ID (defaults to FIRESTORE_PROJECT_ID env var)',
    default: process.env.FIRESTORE_PROJECT_ID,
  })
  .option('collection', {
    type: 'string',
    description: 'Collection name when using --document-id',
    default: 'stores',
  })
  .option('document-id', {
    type: 'string',
    description: 'Document ID inside the collection',
  })
  .option('doc-path', {
    type: 'string',
    description: 'Explicit document path (overrides collection/document-id)',
  })
  .option('location-code', {
    type: 'string',
    description: 'voice_profile.location_code to persist',
    demandOption: true,
  })
  .option('preset-id', {
    type: 'string',
    description: 'Optional preset ID to store alongside the location code',
  })
  .option('locale', {
    type: 'string',
    description: 'Optional locale hint (e.g., fr-FR, fr-CA)',
  })
  .option('dry-run', {
    type: 'boolean',
    default: false,
    description: 'Print the update without writing to Firestore',
  })
  .strict()
  .help()
  .parseSync() as Options;

function resolveDocPath(): string {
  if (argv.docPath) {
    return argv.docPath;
  }
  if (!argv.documentId) {
    throw new Error('Provide either --doc-path or both --collection and --document-id.');
  }
  return `${argv.collection}/${argv.documentId}`;
}

(async () => {
  const projectId = argv.projectId;
  if (!projectId) {
    throw new Error('Set FIRESTORE_PROJECT_ID or pass --project-id.');
  }

  const docPath = resolveDocPath();
  const firestore = new Firestore({ projectId });

  const voiceProfile: Record<string, unknown> = {
    location_code: argv.locationCode,
    updated_at: new Date().toISOString(),
  };

  if (argv.presetId) {
    voiceProfile.preset_id = argv.presetId;
  }
  if (argv.locale) {
    voiceProfile.locale = argv.locale;
  }

  const payload = {
    voice_profile: voiceProfile,
  };

  console.log(`[firestore] Target document: ${docPath}`);
  console.log('[firestore] Payload:', JSON.stringify(payload, null, 2));

  if (argv.dryRun) {
    console.log('[firestore] Dry run enabled, skipping write.');
    return;
  }

  await firestore.doc(docPath).set(payload, { merge: true });
  console.log('[firestore] voice_profile updated successfully.');
})();
