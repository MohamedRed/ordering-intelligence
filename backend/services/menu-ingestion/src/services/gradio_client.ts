import {
  AGENT_BASE_DELAY_MS,
  AGENT_RETRIES,
} from '../config.js';
import { delay } from '../utils.js';
import type { GradioResult } from './ingestion_types.js';

export async function fetchGradio(
  baseUrl: string,
  text: string,
  fileUrl: string,
): Promise<GradioResult | undefined> {
  const form = new FormData();
  form.append('data', text);
  form.append('file', fileUrl);

  const paths = [`${baseUrl}/chat`, `${baseUrl}/chat/`];
  for (let attempt = 1; attempt <= AGENT_RETRIES; attempt++) {
    for (const url of paths) {
      const res = await fetch(url, { method: 'POST', body: form });
      if (res.status === 404) continue;
      if (res.status === 429 || res.status >= 500) {
        if (attempt < AGENT_RETRIES) {
          const backoff = AGENT_BASE_DELAY_MS * Math.pow(2, attempt - 1);
          const jitter = Math.floor(Math.random() * 500);
          await delay(backoff + jitter);
          break;
        }
      }
      try {
        const parsed: any = await res.json();
        const data = parsed?.data ?? parsed;
        if (Array.isArray(data) && data.length) {
          const first = data[0];
          if (typeof first === 'string') return { text: first };
          if (first?.url) return { url: first.url };
          if (first?.path) return { url: first.path };
          if (first?.data) return { inlineData: first.data };
        }
      } catch {
        // Gradio sometimes returns non-JSON error bodies; callers handle undefined.
      }
      return undefined;
    }
  }
  return undefined;
}
