const MENU_OBJECT_MIME_TYPES: Record<string, string> = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.pdf': 'application/pdf',
};

export function resolveMenuObjectMimeType(object: string): string {
  const normalized = String(object ?? '').trim().toLowerCase();
  const extension = normalized.match(/\.[a-z0-9]+$/)?.[0] ?? '';
  const mimeType = MENU_OBJECT_MIME_TYPES[extension];
  if (!mimeType) {
    throw new Error(`unsupported menu upload file type: ${object}`);
  }
  return mimeType;
}
