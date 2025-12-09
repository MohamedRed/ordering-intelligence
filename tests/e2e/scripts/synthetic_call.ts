import 'dotenv/config';

import { Firestore } from '@google-cloud/firestore';
import axios from 'axios';
import { AccessToken } from 'livekit-server-sdk';
import { Twilio } from 'twilio';
import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';
import { GoogleAuth, IdTokenClient } from 'google-auth-library';

type Options = {
  timeout: number;
  pollInterval: number;
  dryRun: boolean;
  requireOrder: boolean;
};

type CompletedOrder = {
  id: string;
  data: FirebaseFirestore.DocumentData;
};

const argv = yargs(hideBin(process.argv))
  .option('timeout', {
    type: 'number',
    default: Number.parseInt(process.env.E2E_TIMEOUT ?? '180000', 10),
    description: 'Maximum time (ms) to wait for call completion/order creation.'
  })
  .option('poll-interval', {
    alias: 'pollInterval',
    type: 'number',
    default: Number.parseInt(process.env.E2E_POLL_INTERVAL ?? '5000', 10),
    description: 'Polling interval (ms) for call status/order checks.'
  })
  .option('dry-run', {
    type: 'boolean',
    default: process.env.DRY_RUN ? process.env.DRY_RUN !== 'false' : true,
    description: 'Skip network calls; validate configuration only.'
  })
  .option('require-order', {
    type: 'boolean',
    default: process.env.E2E_REQUIRE_ORDER === 'true',
    description: 'Fail if matching Firestore order is not created within timeout.'
  })
  .help()
  .parseSync() as Options;

function getEnv(name: string, options: { required?: boolean; fallback?: string } = {}): string | undefined {
  const value = process.env[name] ?? options.fallback;
  if ((value === undefined || value === '') && options.required) {
    throw new Error(`Missing required environment variable ${name}`);
  }
  return value;
}

async function wait(ms: number): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForCallCompletion(client: Twilio, sid: string, timeout: number, pollInterval: number): Promise<string> {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const call = await client.calls(sid).fetch();
    const status = call.status ?? 'unknown';
    if ([
      'completed',
      'failed',
      'busy',
      'no-answer',
      'canceled'
    ].includes(status)) {
      return status;
    }
    await wait(pollInterval);
  }
  throw new Error(`Timed out waiting for call ${sid} to complete`);
}

async function waitForOrder(
  firestore: Firestore,
  collection: string,
  callSid: string,
  timeout: number,
  pollInterval: number
): Promise<CompletedOrder> {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const snapshot = await firestore
      .collection(collection)
      .where('callSid', '==', callSid)
      .limit(1)
      .get();

    if (!snapshot.empty) {
      const doc = snapshot.docs[0];
      return { id: doc.id, data: doc.data() };
    }

    await wait(pollInterval);
  }
  throw new Error(`Timed out waiting for order document for call ${callSid}`);
}

async function waitForOrderViaApi(
  baseUrl: string,
  callSid: string,
  timeout: number,
  pollInterval: number,
  idTokenClient?: IdTokenClient
): Promise<Record<string, unknown>> {
  const deadline = Date.now() + timeout;
  const endpoint = new URL(`/orders/by-call/${callSid}`, baseUrl);
  const requestTimeout = Math.max(10_000, Math.min(20_000, pollInterval));

  while (Date.now() < deadline) {
    try {
      const headers = idTokenClient ? await idTokenClient.getRequestHeaders() : undefined;
      const response = await axios.get(endpoint.toString(), {
        timeout: requestTimeout,
        headers
      });
      if (response.status === 200) {
        return response.data as Record<string, unknown>;
      }
    } catch (error) {
      if (axios.isAxiosError(error) && error.response?.status === 404) {
        // Order not yet created; continue polling.
      } else {
        console.warn('[order-service] Failed to query order API', error);
      }
    }

    await wait(pollInterval);
  }

  throw new Error(`Timed out waiting for order via API for call ${callSid}`);
}

function logDryRunHints(): void {
  console.log('[dry-run] Synthetic call runner executed in dry-run mode.');
  console.log('[dry-run] Set environment variables to execute a live test:');
  console.log('  TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_CALL_FROM, TWILIO_CALL_TO, TWILIO_TWIML_URL');
  console.log('  ORDER_SERVICE_URL (preferred) or FIRESTORE_PROJECT_ID with optional FIRESTORE_ORDER_COLLECTION');
  console.log('  LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET (optional)');
  console.log('Re-run with DRY_RUN=false to trigger real API calls.');
}

async function runRealFlow(options: Options): Promise<void> {
  const twilioSid = getEnv('TWILIO_ACCOUNT_SID', { required: true })!;
  const twilioToken = getEnv('TWILIO_AUTH_TOKEN', { required: true })!;
  const callFrom = getEnv('TWILIO_CALL_FROM', { required: true })!;
  const callTo = getEnv('TWILIO_CALL_TO', { required: true })!;
  const twimlUrl = getEnv('TWILIO_TWIML_URL', { required: true })!;
  const statusCallbackUrl = getEnv('TWILIO_STATUS_CALLBACK_URL');
  const livekitUrl = getEnv('LIVEKIT_URL');
  const livekitKey = getEnv('LIVEKIT_API_KEY');
  const livekitSecret = getEnv('LIVEKIT_API_SECRET');
  const orderServiceUrl = getEnv('ORDER_SERVICE_URL');
  const firestoreProjectId = getEnv('FIRESTORE_PROJECT_ID', { required: options.requireOrder && !orderServiceUrl });
  const firestoreCollection = getEnv('FIRESTORE_ORDER_COLLECTION', { fallback: 'orders' })!;
  const orderApiClient = orderServiceUrl ? await createIdTokenClient(orderServiceUrl) : undefined;

  if (livekitUrl && livekitKey && livekitSecret) {
    const identity = `e2e-${Date.now()}`;
    const token = new AccessToken(livekitKey, livekitSecret, {
      identity,
      ttl: 60 * 10
    });
    token.addGrant({ roomJoin: true, room: `call-${Date.now()}`, canSubscribe: true, canPublish: true });
    console.log(`[livekit] Generated token for identity ${identity}.`);
    console.log(`[livekit] Use when connecting media streams: ${livekitUrl}`);
  } else {
    console.warn('[livekit] Credentials not supplied; skipping token generation.');
  }

  const twilioClient = new Twilio(twilioSid, twilioToken);
  console.log('[twilio] Initiating test call...');
  const call = await twilioClient.calls.create({
    url: twimlUrl,
    to: callTo,
    from: callFrom,
    statusCallback: statusCallbackUrl,
    statusCallbackEvent: statusCallbackUrl ? ['initiated', 'ringing', 'completed'] : undefined
  });
  console.log(`[twilio] Call initiated with SID ${call.sid}. Waiting for completion...`);

  const status = await waitForCallCompletion(twilioClient, call.sid as string, options.timeout, options.pollInterval);
  console.log(`[twilio] Call completed with status ${status}.`);

  if (!options.requireOrder) {
    console.log('[order-check] Order assertion skipped (require-order=false).');
    return;
  }

  if (orderServiceUrl) {
    try {
      const order = await waitForOrderViaApi(
        orderServiceUrl,
        call.sid as string,
        options.timeout,
        options.pollInterval,
        orderApiClient
      );
      console.log(`[order-service] Located order ${order.id ?? '(no id)'} for call ${call.sid}.`);
      return;
    } catch (apiError) {
      console.warn(`[order-service] Order API check failed: ${(apiError as Error).message ?? apiError}`);
      if (!firestoreProjectId) {
        throw apiError;
      }
    }
  }

  if (!firestoreProjectId) {
    throw new Error('ORDER_SERVICE_URL or FIRESTORE_PROJECT_ID must be set when require-order=true');
  }

  const firestore = new Firestore({ projectId: firestoreProjectId });
  console.log(`[firestore] Polling collection '${firestoreCollection}' for callSid=${call.sid}`);
  const order = await waitForOrder(firestore, firestoreCollection, call.sid as string, options.timeout, options.pollInterval);
  console.log(`[firestore] Order ${order.id} located. Items:`, order.data.items ?? order.data);
}

async function createIdTokenClient(baseUrl: string): Promise<IdTokenClient | undefined> {
  try {
    const auth = new GoogleAuth();
    const origin = new URL(baseUrl).origin;
    return await auth.getIdTokenClient(origin);
  } catch (error) {
    console.warn('[order-service] Unable to initialize ID token client; REST checks may fail.', error);
    return undefined;
  }
}

async function main(): Promise<void> {
  const { dryRun } = argv;
  try {
    if (dryRun) {
      logDryRunHints();
      return;
    }
    await runRealFlow(argv);
    console.log('Synthetic call flow completed successfully.');
  } catch (error) {
    console.error('Synthetic call flow failed:');
    console.error(error);
    process.exitCode = 1;
  }
}

void main();
