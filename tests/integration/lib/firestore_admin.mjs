import { getAccessToken } from './gcloud_tokens.mjs';

const toFirestoreValue = (value) => {
  if (value === null || value === undefined) return null;
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (typeof value === 'boolean') return { booleanValue: value };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (Array.isArray(value)) {
    const values = value.map((item) => toFirestoreValue(item)).filter(Boolean);
    return { arrayValue: { values } };
  }
  if (typeof value === 'object') {
    const fields = {};
    for (const [key, item] of Object.entries(value)) {
      const converted = toFirestoreValue(item);
      if (converted) fields[key] = converted;
    }
    return { mapValue: { fields } };
  }
  return { stringValue: String(value) };
};

export const patchFirestoreDoc = async ({ projectId, documentPath, fields }) => {
  if (!projectId) {
    throw new Error('Missing projectId for Firestore patch');
  }
  if (!documentPath) {
    throw new Error('Missing documentPath for Firestore patch');
  }
  const token = getAccessToken();
  const url = new URL(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${documentPath}`
  );
  const fieldKeys = Object.keys(fields || {});
  if (fieldKeys.length === 0) {
    throw new Error('No fields provided for Firestore patch');
  }
  for (const key of fieldKeys) {
    url.searchParams.append('updateMask.fieldPaths', key);
  }
  const payload = { fields: {} };
  for (const [key, value] of Object.entries(fields)) {
    const converted = toFirestoreValue(value);
    if (converted) payload.fields[key] = converted;
  }
  const res = await fetch(url.toString(), {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(payload)
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Firestore patch failed (${res.status}): ${text.slice(0, 300)}`);
  }
  return res.json();
};
