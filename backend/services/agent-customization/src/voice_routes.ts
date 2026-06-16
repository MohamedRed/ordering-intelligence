import type { Express, RequestHandler } from 'express';
import FormData from 'form-data';
import { Timestamp, type Firestore } from '@google-cloud/firestore';
import type { ElevenLabsClient } from './elevenlabs_client.js';

type UploadMiddleware = {
  array(name: string, maxCount?: number): RequestHandler;
};

type VoiceRoutesOptions = {
  upload: UploadMiddleware;
  firestore: Firestore;
  elevenLabs: ElevenLabsClient;
};

export function registerVoiceRoutes(app: Express, options: VoiceRoutesOptions) {
  const { upload, firestore, elevenLabs } = options;

  app.get('/v1/voices', async (_req, res) => {
    try {
      const data = await elevenLabs.json('/v1/voices', { method: 'GET' });
      res.json(data);
    } catch (err: any) {
      res.status(500).json({ error: 'voices_list_failed', message: err.message });
    }
  });

  app.get('/v1/voices/:voiceId', async (req, res) => {
    try {
      const voiceId = req.params.voiceId;
      const data = await elevenLabs.json(`/v1/voices/${encodeURIComponent(voiceId)}`, { method: 'GET' });
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

      const out = await elevenLabs.form<{ voice_id: string; requires_verification?: boolean }>(
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
      const preview = await elevenLabs.previewSpeech({
        voiceId,
        text,
        modelId: req.body?.model_id || 'eleven_multilingual_v2',
      });
      res.setHeader('Content-Type', preview.contentType);
      res.send(preview.buffer);
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
        const created = await elevenLabs.createBranch(agentId, branchName, 'Voice customization');
        branchId = created.branch_id;
      }
      if (!branchId) throw new Error('branch_id_missing');

      await elevenLabs.applyVoiceToAgent({ agentId, branchId, voiceId });

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
        const created = await elevenLabs.createBranch(agentId, branchName, 'Voice customization');
        branchId = created.branch_id;
      }
      if (!branchId) throw new Error('branch_id_missing');

      await elevenLabs.applyVoiceToAgent({ agentId, branchId, voiceId });

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
}
