// Quick harness to exercise the Gradio agent directly (composite) without Vertex.
// Usage:
//   node scripts/test_agent_fallback.js \ 
//     --agent https://genai-app-fastfoodmenudissection-1-1764090756091-230152279015.us-central1.run.app \
//     --key t822bv8mfm23cnfa \
//     --image https://raw.githubusercontent.com/gradio-app/gradio/main/test/test_files/bus.png \
//     --out ./agent_composite.png
//
// Defaults are populated from the values above so you can just run:
//   node scripts/test_agent_fallback.js

import fs from 'node:fs';
import crypto from 'node:crypto';

const argv = Object.fromEntries(
  process.argv.slice(2).map((arg) => {
    const [k, v] = arg.replace(/^--/, '').split('=');
    return [k, v ?? true];
  })
);

const AGENT_BASE =
  argv.agent ||
  process.env.AGENT_COMPOSITE_URL ||
  'https://genai-app-fastfoodmenudissection-1-1764090756091-230152279015.us-central1.run.app';
const AGENT_KEY = argv.key || process.env.AGENT_KEY || 't822bv8mfm23cnfa';
const IMAGE_URL =
  argv.image ||
  process.env.IMAGE_URL ||
  'https://raw.githubusercontent.com/gradio-app/gradio/main/test/test_files/bus.png';
const OUTPUT = argv.out || process.env.OUTPUT || './agent_composite.png';

const session = `sess-${crypto.randomBytes(6).toString('hex')}`;

async function main() {
  console.log('[agent] base', AGENT_BASE);
  console.log('[agent] key', AGENT_KEY ? '(set)' : '(missing)');
  console.log('[agent] image', IMAGE_URL);
  const url = (path) => `${AGENT_BASE}/gradio_api/${path}?key=${AGENT_KEY}`;

  // 1) clear & save textbox (fn_index 0) with message+file
const msg = {
  text: 'Describe this image',
  files: [
    {
      path: IMAGE_URL,
      meta: { _type: 'gradio.FileData' },
    },
  ],
};
  await callPredict(url('run/predict'), {
    data: [msg],
    fn_index: 0,
    trigger_id: 1,
    session_hash: session,
  });

  // 2) append message to history (fn_index 1) — mirrors the UI sequence we observed
  await callPredict(url('run/predict'), {
    data: [msg, []],
    fn_index: 1,
    trigger_id: 2,
    session_hash: session,
  });

  // 3) stream fn (fn_index 2) — expected to return the model output
  const res3 = await callPredict(url('run/predict'), {
    data: [msg, []],
    fn_index: 2,
    trigger_id: 3,
    session_hash: session,
  });

  // Try to extract image or text
  const data = res3?.data;
  console.log('[agent] fn_index 2 response keys', data ? Object.keys(data) : 'none');
  const first = Array.isArray(data) && data.length ? data[0] : undefined;
  if (typeof first === 'string') {
    console.log('[agent] text:', first.slice(0, 200));
    return;
  }
  const maybeUrl = first?.url || first?.path;
  if (maybeUrl) {
    console.log('[agent] downloading', maybeUrl);
    const imgRes = await fetch(maybeUrl);
    if (!imgRes.ok) throw new Error(`download failed ${imgRes.status}`);
    const buf = Buffer.from(await imgRes.arrayBuffer());
    fs.writeFileSync(OUTPUT, buf);
    console.log(`[agent] saved ${OUTPUT} (${buf.length} bytes)`);
    return;
  }
  const inline = first?.data || first?.inlineData;
  if (inline) {
    const buf = Buffer.from(inline, 'base64');
    fs.writeFileSync(OUTPUT, buf);
    console.log(`[agent] saved ${OUTPUT} (${buf.length} bytes)`);
    return;
  }
  console.warn('[agent] could not find image/text payload', res3);
}

async function callPredict(url, body) {
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      referer: `${AGENT_BASE}/?key=${AGENT_KEY}`,
      origin: AGENT_BASE,
    },
    body: JSON.stringify({ ...body, event_data: null }),
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`predict ${body.fn_index} failed ${res.status} ${res.statusText}: ${text.slice(0, 300)}`);
  }
  try {
    return JSON.parse(text);
  } catch (e) {
    console.warn('parse error', e, 'raw:', text.slice(0, 200));
    return undefined;
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
