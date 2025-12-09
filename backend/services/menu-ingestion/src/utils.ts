export function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function slugifyName(name: string): string {
  return (
    name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '_')
      .replace(/^_+|_+$/g, '') || 'item'
  );
}

export function ordinal(n: number): string {
  const s = ['th', 'st', 'nd', 'rd'];
  const v = n % 100;
  return n + (s[(v - 20) % 10] || s[v] || s[0]);
}

export function parseGsUri(uri: string): { bucket: string; object: string } {
  const trimmed = uri.replace(/^gs:\/\//, '');
  const parts = trimmed.split('/');
  const bucket = parts.shift() ?? '';
  const object = parts.join('/');
  return { bucket, object };
}
