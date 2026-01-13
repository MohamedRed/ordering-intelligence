import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import multer from 'multer';
import fetch from 'node-fetch';
import FormData from 'form-data';
import { Firestore, Timestamp } from '@google-cloud/firestore';

const app = express();
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 12 * 1024 * 1024 },
});

const PORT = Number(process.env.PORT) || 8080;
const ELEVENLABS_API_BASE_URL = (process.env.ELEVENLABS_API_BASE_URL || 'https://api.elevenlabs.io').replace(/\/+$/, '');
const ELEVENLABS_API_KEY = (process.env.ELEVENLABS_API_KEY || process.env.XI_API_KEY || '').trim();
const CORS_ORIGINS = (process.env.CORS_ORIGINS || '*')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

const firestore = new Firestore({
  projectId: process.env.FIRESTORE_PROJECT_ID || undefined,
});

app.use(express.json({ limit: '2mb' }));
app.use(cors({
  origin: (origin, callback) => {
    if (!origin || CORS_ORIGINS.includes('*')) {
      callback(null, true);
      return;
    }
    if (CORS_ORIGINS.includes(origin)) {
      callback(null, true);
      return;
    }
    callback(new Error(`CORS blocked for origin: ${origin}`));
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  maxAge: 300,
}));

app.get('/healthz', (_req, res) => {
  res.json({ status: 'ok', service: 'agent-customization' });
});

function requireElevenLabsKey() {
  if (!ELEVENLABS_API_KEY) {
    throw new Error('ELEVENLABS_API_KEY not configured');
  }
}

async function elevenlabsJson<T>(path: string, opts: { method: string; body?: any; headers?: Record<string, string> }): Promise<T> {
  requireElevenLabsKey();
  const url = `${ELEVENLABS_API_BASE_URL}${path}`;
  const resp = await fetch(url, {
    method: opts.method,
    headers: {
      'xi-api-key': ELEVENLABS_API_KEY,
      ...(opts.body ? { 'Content-Type': 'application/json' } : {}),
      ...(opts.headers || {}),
    },
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });
  const text = await resp.text();
  if (!resp.ok) {
    throw new Error(`elevenlabs ${opts.method} ${path} failed status=${resp.status} body=${text.slice(0, 400)}`);
  }
  if (!text.trim()) return {} as T;
  return JSON.parse(text) as T;
}

async function elevenlabsForm<T>(path: string, form: FormData): Promise<T> {
  requireElevenLabsKey();
  const url = `${ELEVENLABS_API_BASE_URL}${path}`;
  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      'xi-api-key': ELEVENLABS_API_KEY,
      ...form.getHeaders(),
    },
    body: form,
  });
  const text = await resp.text();
  if (!resp.ok) {
    throw new Error(`elevenlabs POST ${path} failed status=${resp.status} body=${text.slice(0, 400)}`);
  }
  if (!text.trim()) return {} as T;
  return JSON.parse(text) as T;
}

type BranchInfo = {
  branch_id: string;
  name: string;
  latest_version_id?: string;
};

function normalizeBranches(payload: any): BranchInfo[] {
  let raw: any[] = [];
  if (Array.isArray(payload)) {
    raw = payload;
  } else if (payload && typeof payload === 'object') {
    if (Array.isArray(payload.branches)) raw = payload.branches;
    else if (Array.isArray(payload.results)) raw = payload.results;
    else raw = [payload];
  }
  return raw
    .map((b) => {
      const branch_id = String(b.id || b.branch_id || b.branchId || '').trim();
      const name = String(b.name || b.branch_name || b.branchName || '').trim();
      const versionRecords = Array.isArray(b.versions) ? b.versions : Array.isArray(b.version_records) ? b.version_records : [];
      const latest = versionRecords.length ? versionRecords[0] : undefined;
      const latest_version_id = String(latest?.version_id || latest?.id || latest?.versionId || '').trim();
      return { branch_id, name, latest_version_id };
    })
    .filter((b) => b.branch_id.length > 0);
}

async function tryElevenlabs<T>(method: string, paths: string[], body?: any): Promise<{ path: string; data: T }> {
  let lastErr: any;
  for (const path of paths) {
    try {
      const data = await elevenlabsJson<T>(path, { method, body });
      return { path, data };
    } catch (err) {
      lastErr = err;
    }
  }
  throw lastErr || new Error('ElevenLabs request failed');
}

async function listBranches(agentId: string): Promise<BranchInfo[]> {
  const { data } = await tryElevenlabs<any>('GET', [
    `/v1/convai/agents/${agentId}/branches`,
    `/v1/convai/agents/${agentId}/branches/list`,
  ]);
  return normalizeBranches(data);
}

async function getBranch(agentId: string, branchId: string): Promise<BranchInfo> {
  const { data } = await tryElevenlabs<any>('GET', [
    `/v1/convai/agents/${agentId}/branches/${branchId}`,
    `/v1/convai/agents/${agentId}/branches/get?branch_id=${encodeURIComponent(branchId)}`,
  ]);
  const branches = normalizeBranches(data.branches ?? data);
  const match = branches.find((b) => b.branch_id === branchId);
  return match ?? branches[0] ?? { branch_id: branchId, name: '' };
}

async function enableVersioning(agentId: string): Promise<void> {
  try {
    await elevenlabsJson(`/v1/convai/agents/${agentId}`, {
      method: 'PATCH',
      body: { enable_versioning_if_not_enabled: true },
    });
  } catch (err) {
    console.warn('enable_versioning_if_not_enabled failed', err);
  }
}

async function createBranch(agentId: string, name: string, description: string): Promise<{ branch_id: string; version_id?: string }> {
  await enableVersioning(agentId);
  const branches = await listBranches(agentId);
  if (!branches.length) throw new Error('No branches found; cannot infer main branch');
  const main = branches.find((b) => b.name.toLowerCase() === 'main') || branches[0];
  let parentVersion = main.latest_version_id;
  if (!parentVersion) {
    const full = await getBranch(agentId, main.branch_id);
    parentVersion = full.latest_version_id;
  }
  if (!parentVersion) throw new Error('Unable to infer parent version id');
  const { data } = await tryElevenlabs<any>('POST', [
    `/v1/convai/agents/${agentId}/branches/create`,
    `/v1/convai/agents/${agentId}/branches`,
  ], {
    parent_version_id: parentVersion,
    name,
    description,
  });
  const branch_id = String(data.created_branch_id || data.branch_id || data.id || '').trim();
  const version_id = String(data.created_version_id || data.version_id || data.id || '').trim();
  return { branch_id, version_id };
}

function removeToolsIfToolIdsPresent(body: any) {
  try {
    const promptCfg = body.conversation_config?.agent?.prompt;
    const toolIds = promptCfg?.tool_ids;
    if (Array.isArray(toolIds) && toolIds.length) {
      delete promptCfg.tools;
    }
  } catch (_) {
    // ignore
  }
}

async function fetchAgentConfig(agentId: string, branchId?: string): Promise<any> {
  const suffix = branchId ? `?branch_id=${encodeURIComponent(branchId)}` : '';
  const { data } = await tryElevenlabs<any>('GET', [
    `/v1/convai/agents/${agentId}${suffix}`,
  ]);
  return data;
}

async function patchAgentConfig(agentId: string, branchId: string, config: any): Promise<any> {
  const body: any = { branch_id: branchId };
  for (const key of ['conversation_config', 'platform_settings', 'workflow', 'name', 'tags']) {
    if (config?.[key] !== undefined) body[key] = config[key];
  }
  removeToolsIfToolIdsPresent(body);

  const { data } = await tryElevenlabs<any>('PATCH', [
    `/v1/convai/agents/${agentId}?branch_id=${encodeURIComponent(branchId)}`,
    `/v1/convai/agents/${agentId}?branchId=${encodeURIComponent(branchId)}`,
    `/v1/convai/agents/${agentId}`,
  ], body);
  return data;
}

async function applyVoiceToAgent(params: { agentId: string; branchId: string; voiceId: string }): Promise<void> {
  const remote = await fetchAgentConfig(params.agentId, params.branchId);
  const updated = { ...remote };
  updated.conversation_config = { ...remote.conversation_config };
  updated.conversation_config.tts = { ...remote.conversation_config?.tts, voice_id: params.voiceId };
  await patchAgentConfig(params.agentId, params.branchId, updated);
}

app.get('/v1/voices', async (_req, res) => {
  try {
    const data = await elevenlabsJson('/v1/voices', { method: 'GET' });
    res.json(data);
  } catch (err: any) {
    res.status(500).json({ error: 'voices_list_failed', message: err.message });
  }
});

app.get('/v1/voices/:voiceId', async (req, res) => {
  try {
    const voiceId = req.params.voiceId;
    const data = await elevenlabsJson(`/v1/voices/${encodeURIComponent(voiceId)}`, { method: 'GET' });
    res.json(data);
  } catch (err: any) {
    res.status(500).json({ error: 'voice_get_failed', message: err.message });
  }
});

app.post('/v1/voices', upload.array('files', 8), async (req, res) => {
  try {
    const name = String(req.body?.name || '').trim();
    if (!name) return res.status(400).json({ error: 'missing_name' });
    const files = (req.files as Express.Multer.File[]) || [];
    if (files.length === 0) return res.status(400).json({ error: 'missing_files' });

    const form = new FormData();
    form.append('name', name);
    if (req.body?.description) form.append('description', String(req.body.description));
    if (req.body?.labels) form.append('labels', String(req.body.labels));
    if (req.body?.remove_background_noise !== undefined) {
      const raw = String(req.body.remove_background_noise).toLowerCase();
      const val = raw === 'true' || raw === '1' ? 'true' : 'false';
      form.append('remove_background_noise', val);
    }
    for (const file of files) {
      form.append('files', file.buffer, {
        filename: file.originalname || 'sample',
        contentType: file.mimetype || 'application/octet-stream',
      });
    }

    const out = await elevenlabsForm<{ voice_id: string; requires_verification?: boolean }>(
      '/v1/voices/add',
      form,
    );
    res.json(out);
  } catch (err: any) {
    res.status(500).json({ error: 'voice_create_failed', message: err.message });
  }
});

app.post('/v1/voices/:voiceId/preview', async (req, res) => {
  try {
    const voiceId = req.params.voiceId;
    const text = String(req.body?.text || 'Hello! This is a voice preview.').trim();
    if (!text) return res.status(400).json({ error: 'missing_text' });
    requireElevenLabsKey();
    const url = `${ELEVENLABS_API_BASE_URL}/v1/text-to-speech/${encodeURIComponent(voiceId)}?output_format=mp3_44100_128`;
    const resp = await fetch(url, {
      method: 'POST',
      headers: {
        'xi-api-key': ELEVENLABS_API_KEY,
        'Content-Type': 'application/json',
        Accept: 'audio/mpeg',
      },
      body: JSON.stringify({ text, model_id: req.body?.model_id || 'eleven_multilingual_v2' }),
    });
    if (!resp.ok) {
      const textErr = await resp.text();
      throw new Error(`preview failed status=${resp.status} body=${textErr.slice(0, 300)}`);
    }
    const buf = Buffer.from(await resp.arrayBuffer());
    res.setHeader('Content-Type', resp.headers.get('content-type') || 'audio/mpeg');
    res.send(buf);
  } catch (err: any) {
    res.status(500).json({ error: 'voice_preview_failed', message: err.message });
  }
});

app.get('/v1/onboarding-sessions/:id/voice', async (req, res) => {
  try {
    const id = req.params.id;
    const snap = await firestore.collection('onboarding_sessions').doc(id).get();
    if (!snap.exists) return res.status(404).json({ error: 'session_not_found' });
    const data = snap.data() || {};
    res.json({
      voice_id: data.agent?.voice_id || '',
      branch_id: data.agent?.branch_id || '',
      voice_name: data.agent?.voice_name || '',
    });
  } catch (err: any) {
    res.status(500).json({ error: 'voice_session_get_failed', message: err.message });
  }
});

app.post('/v1/onboarding-sessions/:id/voice', async (req, res) => {
  try {
    const id = req.params.id;
    const voiceId = String(req.body?.voice_id || '').trim();
    const voiceName = String(req.body?.voice_name || '').trim();
    if (!voiceId) return res.status(400).json({ error: 'missing_voice_id' });
    await firestore.collection('onboarding_sessions').doc(id).set({
      agent: {
        voice_id: voiceId,
        voice_name: voiceName,
      },
      updated_at: Timestamp.now(),
    }, { merge: true });
    res.json({ ok: true });
  } catch (err: any) {
    res.status(500).json({ error: 'voice_session_set_failed', message: err.message });
  }
});

app.post('/v1/onboarding-sessions/:id/voice/apply', async (req, res) => {
  try {
    const id = req.params.id;
    const snap = await firestore.collection('onboarding_sessions').doc(id).get();
    if (!snap.exists) return res.status(404).json({ error: 'session_not_found' });
    const data = snap.data() || {};
    const voiceId = String(req.body?.voice_id || data.agent?.voice_id || '').trim();
    if (!voiceId) return res.status(400).json({ error: 'missing_voice_id' });
    const agentId = String(data.agent?.template_agent_id || data.agent?.agent_id || '').trim();
    if (!agentId) return res.status(400).json({ error: 'missing_agent_id' });

    let branchId = String(data.agent?.branch_id || '').trim();
    let branchName = String(req.body?.branch_name || '').trim();
    if (!branchName) branchName = `store-${data.tenant?.store_id || id}`;
    if (!branchId) {
      const created = await createBranch(agentId, branchName, 'Voice customization');
      branchId = created.branch_id;
    }
    if (!branchId) throw new Error('branch_id_missing');

    await applyVoiceToAgent({ agentId, branchId, voiceId });

    await firestore.collection('onboarding_sessions').doc(id).set({
      agent: {
        voice_id: voiceId,
        branch_id: branchId,
        voice_name: data.agent?.voice_name || '',
      },
      updated_at: Timestamp.now(),
    }, { merge: true });

    res.json({ ok: true, voice_id: voiceId, branch_id: branchId, agent_id: agentId });
  } catch (err: any) {
    res.status(500).json({ error: 'voice_apply_failed', message: err.message });
  }
});

app.get('/v1/stores/:storeId/voice', async (req, res) => {
  try {
    const storeId = req.params.storeId;
    const snap = await firestore.collection('stores').doc(storeId).get();
    if (!snap.exists) return res.status(404).json({ error: 'store_not_found' });
    const data = snap.data() || {};
    res.json({
      voice_id: data.elevenlabs_voice_id || '',
      branch_id: data.elevenlabs_agent_branch_id || '',
      agent_id: data.elevenlabs_agent_id || data.elevenlabs_agent_template_id || '',
    });
  } catch (err: any) {
    res.status(500).json({ error: 'voice_store_get_failed', message: err.message });
  }
});

app.post('/v1/stores/:storeId/voice', async (req, res) => {
  try {
    const storeId = req.params.storeId;
    const voiceId = String(req.body?.voice_id || '').trim();
    if (!voiceId) return res.status(400).json({ error: 'missing_voice_id' });

    const storeRef = firestore.collection('stores').doc(storeId);
    const snap = await storeRef.get();
    if (!snap.exists) return res.status(404).json({ error: 'store_not_found' });
    const data = snap.data() || {};

    const agentId = String(data.elevenlabs_agent_id || data.elevenlabs_agent_template_id || '').trim();
    if (!agentId) return res.status(400).json({ error: 'missing_agent_id' });

    let branchId = String(data.elevenlabs_agent_branch_id || '').trim();
    let branchName = String(data.elevenlabs_agent_branch_name || '').trim();
    if (!branchName) branchName = `store-${storeId}`;
    if (!branchId) {
      const created = await createBranch(agentId, branchName, 'Voice customization');
      branchId = created.branch_id;
    }
    if (!branchId) throw new Error('branch_id_missing');

    await applyVoiceToAgent({ agentId, branchId, voiceId });

    await storeRef.set({
      elevenlabs_voice_id: voiceId,
      elevenlabs_agent_branch_id: branchId,
      elevenlabs_agent_branch_name: branchName,
      updated_at: Timestamp.now(),
    }, { merge: true });

    res.json({ ok: true, voice_id: voiceId, branch_id: branchId, agent_id: agentId });
  } catch (err: any) {
    res.status(500).json({ error: 'voice_store_set_failed', message: err.message });
  }
});

app.listen(PORT, () => {
  console.log(`agent-customization listening on :${PORT}`);
});
