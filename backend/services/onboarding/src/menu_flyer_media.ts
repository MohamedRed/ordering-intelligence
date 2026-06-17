export type MenuFlyerMedia = {
  extension: string;
  contentType: string;
};

const MENU_FLYER_MEDIA_TYPES: Record<string, string> = {
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
};

export function resolveMenuFlyerMediaFromFilename(filename: string): MenuFlyerMedia | undefined {
  const extension = extensionFromFilename(filename);
  const contentType = extension ? MENU_FLYER_MEDIA_TYPES[extension] : undefined;
  return contentType ? { extension, contentType } : undefined;
}

export function resolveMenuFlyerMediaFromUrl(urlOrKey: string): MenuFlyerMedia | undefined {
  const path = pathnameFromUrlOrKey(urlOrKey);
  return resolveMenuFlyerMediaFromFilename(path);
}

export function isAllowedMenuFlyerContentType(contentType: string, extension: string): boolean {
  return MENU_FLYER_MEDIA_TYPES[extension] === contentType.toLowerCase();
}

function pathnameFromUrlOrKey(urlOrKey: string): string {
  try {
    return new URL(urlOrKey).pathname;
  } catch {
    return urlOrKey;
  }
}

function extensionFromFilename(filename: string): string {
  const withoutQuery = filename.split('?')[0].split('#')[0];
  const parts = withoutQuery.split('.');
  return parts.length > 1 ? (parts.pop() ?? '').toLowerCase() : '';
}
