import 'dotenv/config';

import fs from 'node:fs';
import path from 'node:path';

import axios from 'axios';
import { Firestore } from '@google-cloud/firestore';
import { Storage, File } from '@google-cloud/storage';
import { GoogleAuth } from 'google-auth-library';

const baseUrl = reqEnv('MENU_INGESTION_BASE_URL');
const restaurantId = reqEnv('MENU_INGESTION_RESTAURANT_ID');
const samplePath = reqEnv('MENU_INGESTION_SAMPLE_PATH');
const projectId = reqEnv('GOOGLE_CLOUD_PROJECT');
const firebaseApiKey = process.env.FIREBASE_API_KEY ?? 'AIzaSyAyva47VFazHoIHMkQVJ7j9_preZIyFlvI';
const firebaseUser = process.env.FIREBASE_USER ?? 'admin-tester@example.com';
const firebasePass = process.env.FIREBASE_PASS ?? 'AdminTest123!';

async function main() {
  console.log('--- step 1: start');
  const startResp = await axios.post(`${baseUrl}/ingest/start`, {
    restaurantId,
    pageCount: 1,
  });
  const jobId: string = startResp.data.jobId;
  const uploadUrl: string = startResp.data.uploadUrls?.[0];
  console.log({ jobId, uploadUrl });

  console.log('--- step 2: upload sample');
  const fileBuf = fs.readFileSync(samplePath);
  await axios.put(uploadUrl, fileBuf, {
    headers: { 'Content-Type': inferMime(samplePath) },
    maxContentLength: Infinity,
    maxBodyLength: Infinity,
  });
  console.log('upload complete');

  console.log('--- step 3: submit');
  await axios.post(`${baseUrl}/ingest/submit`, { jobId });
  console.log('queued');

  console.log('--- step 4: poll job status');
  const status = await waitForReady(baseUrl, jobId, 30, 5000);
  console.log('final status', status);

  const firestore = new Firestore({ projectId });
  const jobSnap = await firestore.collection('menus_ingest').doc(jobId).get();
  console.log('job doc', jobSnap.exists ? jobSnap.data() : 'missing');

  if (status.status !== 'ready') return;

  console.log('--- step 5: draft fetch');
  const idToken = await getIdToken();
  const draftResp = await axios.get(`${baseUrl}/ingest/${jobId}/draft`, {
    headers: { Authorization: `Bearer ${idToken}` },
  });
  const draft = draftResp.data?.draft ?? {};
  console.log('draft counts', {
    items: draft.items?.length ?? 0,
    compositeUrls: draft.compositeUrls?.length ?? 0,
    detectedItemCount: draft.detectedItemCount ?? null,
  });
  if (draft.compositeUrls?.length) {
    console.log('composites:', draft.compositeUrls);
  }

  const storage = new Storage({ projectId });
  console.log('--- step 6: storage artifacts');
  const bucket = storage.bucket(reqEnv('MENU_BUCKET', 'ordering-intelligence-menus-dev'));
  const [files] = await bucket.getFiles({ prefix: `menu-` });
  const ours = files
    .map((f: File) => f.name)
    .filter((n: string) => n.includes(jobId));
  console.log(`found ${ours.length} objects for job`, ours);

  console.log('--- done');
}

type JobStatus = { status: string };

async function waitForReady(baseUrl: string, jobId: string, attempts: number, delayMs: number) {
  for (let i = 0; i < attempts; i++) {
    const resp = await axios.get<JobStatus>(`${baseUrl}/ingest/${jobId}`);
    if (resp.data.status === 'ready' || resp.data.status === 'error') return resp.data;
    await new Promise((r) => setTimeout(r, delayMs));
  }
  throw new Error('Timed out waiting for job to be ready');
}

function inferMime(p: string): string {
  const ext = path.extname(p).toLowerCase();
  if (ext === '.png') return 'image/png';
  if (ext === '.jpg' || ext === '.jpeg') return 'image/jpeg';
  if (ext === '.pdf') return 'application/pdf';
  return 'application/octet-stream';
}

function reqEnv(name: string, def?: string): string {
  const val = process.env[name] ?? def;
  if (!val) throw new Error(`Missing env ${name}`);
  return val;
}

async function getIdToken(): Promise<string> {
  const resp = await axios.post(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${firebaseApiKey}`,
    {
      email: firebaseUser,
      password: firebasePass,
      returnSecureToken: true,
    }
  );
  return resp.data.idToken as string;
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
