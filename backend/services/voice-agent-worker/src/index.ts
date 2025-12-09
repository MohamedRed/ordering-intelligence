import 'dotenv/config';

import { fileURLToPath } from 'node:url';

import { cli } from '@livekit/agents';

import { createWorkerOptions } from './runtime/worker';

const agentPath = fileURLToPath(import.meta.url);

if (process.argv[1] === agentPath) {
  cli.runApp(createWorkerOptions(agentPath));
}
