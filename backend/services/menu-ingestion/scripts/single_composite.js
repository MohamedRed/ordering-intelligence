// One-off helper to call Gemini 3 Pro Image Preview once for a single page.
// Usage:
//   GOOGLE_CLOUD_PROJECT=ordering-intelligence \
//   FILE_URI=gs://ordering-intelligence-menus-dev/menu-raw/restaurant/job/page-1.jpg \
//   OUTPUT=./composite.png \
//   node scripts/single_composite.js

import { GoogleAuth } from 'google-auth-library';
import fs from 'node:fs';

const PROJECT = process.env.GOOGLE_CLOUD_PROJECT || process.env.GCP_PROJECT;
const LOCATION = 'global';
const MODEL = process.env.MODEL_ID || 'gemini-3-pro-image-preview';
const FILE_URI = process.env.FILE_URI;
const OUTPUT = process.env.OUTPUT || './composite.png';

if (!PROJECT) throw new Error('GOOGLE_CLOUD_PROJECT required');
if (!FILE_URI) throw new Error('FILE_URI required (gs://bucket/object)');

const PROMPT =
  'So this is a page, a part of a menu of fast food containing different items, bundles, etc, probably organized by categories, with maybe a text next to each item with a price probably, or maybe a description. ' +
  'Can you separate all of these purchasable elements of the menu in a composite in order to use them as thumbnails into a menu visualizer for the personnel of the fast food and the clients? ' +
  'Keep each dish together with its text and price. Output one image with all separated dishes neatly laid out on white.';

async function main() {
  const auth = new GoogleAuth({ scopes: 'https://www.googleapis.com/auth/cloud-platform' });
  const token = await auth.getAccessToken();

  const url = `https://aiplatform.googleapis.com/v1/projects/${PROJECT}/locations/${LOCATION}/publishers/google/models/${MODEL}:generateContent`;

  const body = {
    contents: [
      {
        role: 'user',
        parts: [
          { text: PROMPT },
          { fileData: { fileUri: FILE_URI, mimeType: 'image/jpeg' } },
        ],
      },
    ],
    generationConfig: {
      responseModalities: ['TEXT', 'IMAGE'],
      maxOutputTokens: 32768,
      temperature: 1,
      topP: 0.95,
      imageConfig: {
        aspectRatio: '1:1',
        imageSize: '1K',
      },
    },
    safetySettings: [
      { category: 'HARM_CATEGORY_HATE_SPEECH', threshold: 'OFF' },
      { category: 'HARM_CATEGORY_DANGEROUS_CONTENT', threshold: 'OFF' },
      { category: 'HARM_CATEGORY_SEXUALLY_EXPLICIT', threshold: 'OFF' },
      { category: 'HARM_CATEGORY_HARASSMENT', threshold: 'OFF' },
    ],
  };

  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  const resText = await res.text();
  if (!res.ok) {
    throw new Error(`status ${res.status} ${res.statusText}: ${resText.slice(0, 400)}`);
  }

  const parsed = JSON.parse(resText);
  const part = parsed?.candidates
    ?.flatMap((c) => c?.content?.parts ?? [])
    ?.find((p) => p?.inlineData?.data || p?.data);
  const imageB64 = part?.inlineData?.data ?? part?.data;
  if (!imageB64) throw new Error('No image in response');

  const buf = Buffer.from(imageB64, 'base64');
  fs.writeFileSync(OUTPUT, buf);
  console.log(`Wrote composite to ${OUTPUT} (${buf.length} bytes)`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
