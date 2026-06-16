import express, { type Express, type Response } from 'express';
import multer from 'multer';
import { v4 as uuidv4 } from 'uuid';

type StorageFile = {
  save: (buffer: Buffer, options: Record<string, unknown>) => Promise<unknown>;
  delete: (options: { ignoreNotFound: boolean }) => Promise<unknown>;
  getSignedUrl: (options: { action: 'read'; expires: number }) => Promise<[string]>;
};

type StorageBucket = {
  name: string;
  file: (key: string) => StorageFile;
};

type RegisterMenuFlyerUploadRoutesParams = {
  app: Express;
  bucket: StorageBucket;
  publicBaseUrl?: string;
  makePublic: boolean;
  maxUploadBytes?: number;
};

export const MENU_FLYER_PREFIX = 'menu-flyers/';
export const DEFAULT_MENU_FLYER_MAX_UPLOAD_BYTES = 10 * 1024 * 1024;

const ALLOWED_TYPES: Record<string, string[]> = {
  'image/jpeg': ['jpg', 'jpeg'],
  'image/png': ['png'],
  'image/webp': ['webp'],
};

class MenuFlyerUploadError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'MenuFlyerUploadError';
  }
}

export function resolveMenuFlyerMaxUploadBytes(env: NodeJS.ProcessEnv = process.env): number {
  const raw = env.MENU_FLYER_MAX_UPLOAD_BYTES;
  if (raw == null || raw.trim() === '') return DEFAULT_MENU_FLYER_MAX_UPLOAD_BYTES;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1) {
    throw new Error('MENU_FLYER_MAX_UPLOAD_BYTES must be a positive integer');
  }
  return value;
}

export function validateMenuFlyerUploadFile(params: {
  originalname: string;
  mimetype?: string;
}): { extension: string; contentType: string; safeName: string } {
  const safeName = sanitizeFilename(params.originalname);
  const extension = extensionFromFilename(safeName);
  const contentType = (params.mimetype ?? '').toLowerCase();
  const allowedExtensions = ALLOWED_TYPES[contentType];
  if (!allowedExtensions || !allowedExtensions.includes(extension)) {
    throw new MenuFlyerUploadError(
      415,
      'unsupported_menu_flyer_type',
      'Menu flyer uploads must be JPEG, PNG, or WebP images.',
    );
  }
  return { extension, contentType, safeName };
}

export function assertMenuFlyerKey(key: unknown): asserts key is string {
  if (typeof key !== 'string' || !key.startsWith(MENU_FLYER_PREFIX) || key.includes('..')) {
    throw new MenuFlyerUploadError(
      400,
      'invalid_menu_flyer_key',
      'Menu flyer key is required and must target the menu-flyers prefix.',
    );
  }
}

export function registerMenuFlyerUploadRoutes(params: RegisterMenuFlyerUploadRoutesParams): void {
  const maxUploadBytes = params.maxUploadBytes ?? resolveMenuFlyerMaxUploadBytes();
  const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: maxUploadBytes, files: 1 },
    fileFilter: (_req, file, cb) => {
      try {
        validateMenuFlyerUploadFile({
          originalname: file.originalname,
          mimetype: file.mimetype,
        });
        cb(null, true);
      } catch (err) {
        cb(err as Error);
      }
    },
  });

  params.app.post(
    '/uploads/menu-flyer',
    (req, res, next) => {
      upload.single('file')(req, res, (err) => {
        if (err) return handleUploadError(err, res, maxUploadBytes);
        return next();
      });
    },
    async (req, res) => {
      try {
        if (!req.file) {
          return res.status(400).json({ error: 'file_required', message: 'file is required (field "file")' });
        }
        const fileMeta = validateMenuFlyerUploadFile({
          originalname: req.file.originalname,
          mimetype: req.file.mimetype,
        });
        const key = `${MENU_FLYER_PREFIX}${uuidv4()}-${fileMeta.safeName}`;
        const file = params.bucket.file(key);
        await file.save(req.file.buffer, {
          resumable: false,
          contentType: fileMeta.contentType,
          metadata: {
            cacheControl: 'public, max-age=86400',
          },
        });

        const url = await resolveFlyerUrl({
          file,
          bucket: params.bucket,
          key,
          makePublic: params.makePublic,
          publicBaseUrl: params.publicBaseUrl,
        });

        return res.status(201).json({
          url,
          key,
          bucket: params.bucket.name,
          contentType: fileMeta.contentType,
          ext: fileMeta.extension,
        });
      } catch (err) {
        if (err instanceof MenuFlyerUploadError) {
          return res.status(err.statusCode).json({ error: err.code, message: err.message });
        }
        console.error('Upload failed', err);
        return res.status(500).json({ error: 'upload_failed' });
      }
    },
  );

  params.app.delete('/uploads/menu-flyer', express.json(), async (req, res) => {
    try {
      const key = req.body?.key;
      assertMenuFlyerKey(key);
      await params.bucket.file(key).delete({ ignoreNotFound: true });
      return res.status(204).send();
    } catch (err) {
      if (err instanceof MenuFlyerUploadError) {
        return res.status(err.statusCode).json({ error: err.code, message: err.message });
      }
      console.error('Delete flyer failed', err);
      return res.status(500).json({ error: 'delete_failed' });
    }
  });
}

function handleUploadError(err: unknown, res: Response, maxUploadBytes: number): void {
  if (err instanceof MenuFlyerUploadError) {
    res.status(err.statusCode).json({ error: err.code, message: err.message });
    return;
  }
  if (err instanceof multer.MulterError && err.code === 'LIMIT_FILE_SIZE') {
    res.status(413).json({
      error: 'menu_flyer_too_large',
      message: `Menu flyer uploads must be ${maxUploadBytes} bytes or smaller.`,
      maxUploadBytes,
    });
    return;
  }
  console.error('Upload middleware failed', err);
  res.status(500).json({ error: 'upload_failed' });
}

async function resolveFlyerUrl(params: {
  file: StorageFile;
  bucket: StorageBucket;
  key: string;
  makePublic: boolean;
  publicBaseUrl?: string;
}): Promise<string> {
  if (params.makePublic) {
    const [signed] = await params.file.getSignedUrl({
      action: 'read',
      expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
    });
    return signed;
  }
  const baseUrl = params.publicBaseUrl?.replace(/\/$/, '') || `https://storage.googleapis.com/${params.bucket.name}`;
  return `${baseUrl}/${params.key}`;
}

function extensionFromFilename(filename: string): string {
  const parts = filename.split('.');
  return parts.length > 1 ? (parts.pop() ?? '').toLowerCase() : '';
}

function sanitizeFilename(filename: string): string {
  const basename = filename.split(/[\\/]/).pop() || 'menu-flyer';
  const cleaned = basename.replace(/[^a-zA-Z0-9._-]/g, '-').replace(/-+/g, '-');
  return cleaned || 'menu-flyer';
}
