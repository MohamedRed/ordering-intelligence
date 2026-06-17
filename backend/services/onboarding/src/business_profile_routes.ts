import type { Express, Response } from 'express';
import { Timestamp, type CollectionReference } from '@google-cloud/firestore';

type BusinessProfileSession = {
  flyers?: string[];
};

type PrefillVertexClient = {
  getGenerativeModel: (params: { model: string }) => {
    generateContent: (request: any) => Promise<{
      response?: {
        candidates?: Array<{
          content?: {
            parts?: Array<{ text?: string }>;
          };
        }>;
      };
    }>;
  };
};

type RegisterBusinessProfileRoutesParams = {
  app: Express;
  sessions: CollectionReference;
  vertex: PrefillVertexClient | null;
  prefillModel: string;
  getSession: (id: string, res: Response) => Promise<(BusinessProfileSession & { id: string }) | null>;
  audit: (id: string, event: string, data?: unknown) => Promise<void>;
};

export function registerBusinessProfileRoutes(params: RegisterBusinessProfileRoutesParams): void {
  params.app.post('/onboarding-sessions/:id/prefill', async (req, res) => {
    try {
      const { id } = req.params;
      const snap = await params.getSession(id, res);
      if (!snap) return;
      if (!params.vertex) return res.status(500).json({ error: 'vertex_not_configured' });
      const flyers = snap.flyers ?? [];
      if (flyers.length === 0) return res.status(400).json({ error: 'no_flyers' });

      const prefill = await generateBusinessPrefill(params.vertex, params.prefillModel, flyers);
      await params.sessions.doc(id).update({
        prefill,
        status: 'prefill_ready',
        updated_at: Timestamp.now(),
      });
      await params.audit(id, 'prefill_generated');
      return res.json({ prefill });
    } catch (err: any) {
      console.error('prefill error', err);
      return res.status(500).json({ error: 'prefill_failed', message: err.message });
    }
  });

  params.app.patch('/onboarding-sessions/:id/business-details', async (req, res) => {
    try {
      const { id } = req.params;
      const snap = await params.getSession(id, res);
      if (!snap) return;
      await params.sessions.doc(id).update({ business: req.body, updated_at: Timestamp.now() });
      await params.audit(id, 'business_updated', req.body);
      return res.json({ ok: true });
    } catch (err: any) {
      console.error('business-details error', err);
      return res.status(500).json({ error: 'business_update_failed', message: err.message });
    }
  });
}

export async function generateBusinessPrefill(
  vertex: PrefillVertexClient,
  prefillModel: string,
  flyers: string[],
): Promise<{ model: string; raw: string; parsed: any }> {
  const model = vertex.getGenerativeModel({ model: prefillModel });
  const result = await model.generateContent({
    contents: [{ role: 'user', parts: [{ text: buildBusinessPrefillPrompt(flyers) }] }],
    generationConfig: { temperature: 0.2, maxOutputTokens: 512 },
  });
  const raw = extractTextParts(result);
  return {
    model: prefillModel,
    raw,
    parsed: parseFirstJsonObject(raw),
  };
}

function buildBusinessPrefillPrompt(flyers: string[]): string {
  return `
You are extracting business profile and menu hints from image URLs (flyers).
Return compact JSON with keys: business_name, address, phone, hours (string), categories (array of strings), notes.
Keep null when unknown. Do not include any extra fields.
Flyer URLs:
${flyers.join('\n')}
`;
}

function extractTextParts(result: Awaited<ReturnType<ReturnType<PrefillVertexClient['getGenerativeModel']>['generateContent']>>): string {
  return result.response?.candidates?.[0]?.content?.parts?.map((part) => part.text).join(' ') || '';
}

function parseFirstJsonObject(text: string): any {
  try {
    const jsonMatch = text.match(/\{[\s\S]*\}/);
    if (jsonMatch) return JSON.parse(jsonMatch[0]);
  } catch {
    return { raw: text };
  }
  return { raw: text };
}
