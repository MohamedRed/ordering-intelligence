import fetch from 'node-fetch';
import FormData from 'form-data';

type JsonOptions = {
  method: string;
  body?: unknown;
  headers?: Record<string, string>;
};

type BranchInfo = {
  branch_id: string;
  name: string;
  latest_version_id?: string;
};

export type SpeechPreview = {
  buffer: Buffer;
  contentType: string;
};

export type ElevenLabsClient = {
  json<T>(path: string, opts: JsonOptions): Promise<T>;
  form<T>(path: string, form: FormData): Promise<T>;
  createBranch(agentId: string, name: string, description: string): Promise<{ branch_id: string; version_id?: string }>;
  applyVoiceToAgent(params: { agentId: string; branchId: string; voiceId: string }): Promise<void>;
  previewSpeech(params: { voiceId: string; text: string; modelId?: string }): Promise<SpeechPreview>;
};

export function createElevenLabsClient(params: { apiKey: string; baseUrl: string }): ElevenLabsClient {
  const apiKey = params.apiKey.trim();
  const baseUrl = params.baseUrl.replace(/\/+$/, '');

  function requireElevenLabsKey() {
    if (!apiKey) {
      throw new Error('ELEVENLABS_API_KEY not configured');
    }
  }

  async function json<T>(path: string, opts: JsonOptions): Promise<T> {
    requireElevenLabsKey();
    const url = `${baseUrl}${path}`;
    const resp = await fetch(url, {
      method: opts.method,
      headers: {
        'xi-api-key': apiKey,
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

  async function form<T>(path: string, payload: FormData): Promise<T> {
    requireElevenLabsKey();
    const url = `${baseUrl}${path}`;
    const resp = await fetch(url, {
      method: 'POST',
      headers: {
        'xi-api-key': apiKey,
        ...payload.getHeaders(),
      },
      body: payload,
    });
    const text = await resp.text();
    if (!resp.ok) {
      throw new Error(`elevenlabs POST ${path} failed status=${resp.status} body=${text.slice(0, 400)}`);
    }
    if (!text.trim()) return {} as T;
    return JSON.parse(text) as T;
  }

  async function previewSpeech(params: { voiceId: string; text: string; modelId?: string }): Promise<SpeechPreview> {
    requireElevenLabsKey();
    const url = `${baseUrl}/v1/text-to-speech/${encodeURIComponent(params.voiceId)}?output_format=mp3_44100_128`;
    const resp = await fetch(url, {
      method: 'POST',
      headers: {
        'xi-api-key': apiKey,
        'Content-Type': 'application/json',
        Accept: 'audio/mpeg',
      },
      body: JSON.stringify({ text: params.text, model_id: params.modelId || 'eleven_multilingual_v2' }),
    });
    if (!resp.ok) {
      const textErr = await resp.text();
      throw new Error(`preview failed status=${resp.status} body=${textErr.slice(0, 300)}`);
    }
    return {
      buffer: Buffer.from(await resp.arrayBuffer()),
      contentType: resp.headers.get('content-type') || 'audio/mpeg',
    };
  }

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
      .map((branch) => {
        const branch_id = String(branch.id || branch.branch_id || branch.branchId || '').trim();
        const name = String(branch.name || branch.branch_name || branch.branchName || '').trim();
        const versionRecords = Array.isArray(branch.versions)
          ? branch.versions
          : Array.isArray(branch.version_records)
            ? branch.version_records
            : [];
        const latest = versionRecords.length ? versionRecords[0] : undefined;
        const latest_version_id = String(latest?.version_id || latest?.id || latest?.versionId || '').trim();
        return { branch_id, name, latest_version_id };
      })
      .filter((branch) => branch.branch_id.length > 0);
  }

  async function tryElevenlabs<T>(method: string, paths: string[], body?: unknown): Promise<{ path: string; data: T }> {
    let lastErr: unknown;
    for (const path of paths) {
      try {
        const data = await json<T>(path, { method, body });
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
    const match = branches.find((branch) => branch.branch_id === branchId);
    return match ?? branches[0] ?? { branch_id: branchId, name: '' };
  }

  async function enableVersioning(agentId: string): Promise<void> {
    try {
      await json(`/v1/convai/agents/${agentId}`, {
        method: 'PATCH',
        body: { enable_versioning_if_not_enabled: true },
      });
    } catch (err) {
      console.warn('enable_versioning_if_not_enabled failed', err);
    }
  }

  async function createBranch(
    agentId: string,
    name: string,
    description: string,
  ): Promise<{ branch_id: string; version_id?: string }> {
    await enableVersioning(agentId);
    const branches = await listBranches(agentId);
    if (!branches.length) throw new Error('No branches found; cannot infer main branch');
    const main = branches.find((branch) => branch.name.toLowerCase() === 'main') || branches[0];
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

  return {
    json,
    form,
    createBranch,
    applyVoiceToAgent,
    previewSpeech,
  };
}
