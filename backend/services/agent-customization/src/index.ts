import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import multer from 'multer';
import { Firestore } from '@google-cloud/firestore';
import { buildCorsOptions, resolveCorsOrigins } from './cors_policy.js';
import { createElevenLabsClient } from './elevenlabs_client.js';
import { registerVoiceRoutes } from './voice_routes.js';

const app = express();
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 12 * 1024 * 1024 },
});

const PORT = Number(process.env.PORT) || 8080;
const ENVIRONMENT = (process.env.ENVIRONMENT || process.env.NODE_ENV || 'development').trim();
const ELEVENLABS_API_BASE_URL = (process.env.ELEVENLABS_API_BASE_URL || 'https://api.elevenlabs.io').replace(/\/+$/, '');
const ELEVENLABS_API_KEY = (process.env.ELEVENLABS_API_KEY || process.env.XI_API_KEY || '').trim();
const CORS_ORIGINS = resolveCorsOrigins(process.env.CORS_ORIGINS, ENVIRONMENT);

const firestore = new Firestore({
  projectId: process.env.FIRESTORE_PROJECT_ID || undefined,
});
const elevenLabs = createElevenLabsClient({
  apiKey: ELEVENLABS_API_KEY,
  baseUrl: ELEVENLABS_API_BASE_URL,
});

app.use(express.json({ limit: '2mb' }));
app.use(cors(buildCorsOptions(CORS_ORIGINS)));

app.get('/healthz', (_req, res) => {
  res.json({ status: 'ok', service: 'agent-customization' });
});

registerVoiceRoutes(app, {
  upload,
  firestore,
  elevenLabs,
});

app.listen(PORT, () => {
  console.log(`agent-customization listening on :${PORT}`);
});
