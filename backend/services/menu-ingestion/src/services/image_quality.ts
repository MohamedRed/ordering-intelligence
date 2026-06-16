import { Storage } from '@google-cloud/storage';
import sharp from 'sharp';
import { bucketEnv as BUCKET_ENV } from '../config.js';

export type ImageQualityLimits = {
  minShortEdge: number;
  minLongEdge: number;
  maxPixels: number;
  minLaplacianVariance: number;
};

export type ImageQualityReport = {
  object: string;
  width: number;
  height: number;
  pixels: number;
  laplacianVariance: number;
};

export class ImageQualityError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly details: Record<string, number | string> = {},
  ) {
    super(message);
    this.name = 'ImageQualityError';
  }
}

const DEFAULT_LIMITS: ImageQualityLimits = {
  minShortEdge: 600,
  minLongEdge: 800,
  maxPixels: 25_000_000,
  minLaplacianVariance: 25,
};

const storage = new Storage();
const BUCKET = (BUCKET_ENV || '') as string;

function readPositiveNumber(
  env: NodeJS.ProcessEnv,
  name: string,
  fallback: number,
): number {
  const raw = env[name];
  if (raw == null || raw.trim() === '') return fallback;
  const value = Number(raw);
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error(`${name} must be a positive number`);
  }
  return value;
}

export function loadImageQualityLimits(
  env: NodeJS.ProcessEnv = process.env,
): ImageQualityLimits {
  return {
    minShortEdge: readPositiveNumber(
      env,
      'MENU_MIN_IMAGE_SHORT_EDGE',
      DEFAULT_LIMITS.minShortEdge,
    ),
    minLongEdge: readPositiveNumber(
      env,
      'MENU_MIN_IMAGE_LONG_EDGE',
      DEFAULT_LIMITS.minLongEdge,
    ),
    maxPixels: readPositiveNumber(env, 'MENU_MAX_IMAGE_PIXELS', DEFAULT_LIMITS.maxPixels),
    minLaplacianVariance: readPositiveNumber(
      env,
      'MENU_MIN_LAPLACIAN_VARIANCE',
      DEFAULT_LIMITS.minLaplacianVariance,
    ),
  };
}

export const imageQualityLimits = loadImageQualityLimits();

export async function validateMenuImages(
  files: string[],
  options: { bucketName?: string; limits?: ImageQualityLimits } = {},
): Promise<ImageQualityReport[]> {
  const bucketName = options.bucketName ?? BUCKET;
  const limits = options.limits ?? imageQualityLimits;
  const reports: ImageQualityReport[] = [];
  for (const object of files) {
    const [buffer] = await storage.bucket(bucketName).file(object).download();
    reports.push(await assessMenuImageBuffer(buffer, object, limits));
  }
  return reports;
}

export async function assessMenuImageBuffer(
  buffer: Buffer,
  object = 'uploaded image',
  limits: ImageQualityLimits = imageQualityLimits,
): Promise<ImageQualityReport> {
  let metadata: sharp.Metadata;
  try {
    metadata = await sharp(buffer, { failOn: 'error' }).metadata();
  } catch {
    throw new ImageQualityError('invalid_image', `${object} is not a readable image`, { object });
  }

  const width = metadata.width ?? 0;
  const height = metadata.height ?? 0;
  if (!width || !height) {
    throw new ImageQualityError('invalid_image', `${object} is missing image dimensions`, { object });
  }

  const pixels = width * height;
  const shortEdge = Math.min(width, height);
  const longEdge = Math.max(width, height);
  if (shortEdge < limits.minShortEdge || longEdge < limits.minLongEdge) {
    throw new ImageQualityError('low_resolution_image', `${object} is below menu image resolution limits`, {
      object,
      width,
      height,
      minShortEdge: limits.minShortEdge,
      minLongEdge: limits.minLongEdge,
    });
  }
  if (pixels > limits.maxPixels) {
    throw new ImageQualityError('oversized_image', `${object} exceeds menu image pixel limits`, {
      object,
      width,
      height,
      maxPixels: limits.maxPixels,
    });
  }

  const laplacianVariance = await computeLaplacianVariance(buffer);
  if (laplacianVariance < limits.minLaplacianVariance) {
    throw new ImageQualityError('blurry_image', `${object} is too blurry for reliable menu extraction`, {
      object,
      laplacianVariance,
      minLaplacianVariance: limits.minLaplacianVariance,
    });
  }

  return { object, width, height, pixels, laplacianVariance };
}

async function computeLaplacianVariance(buffer: Buffer): Promise<number> {
  const { data, info } = await sharp(buffer, { failOn: 'error' })
    .resize({ width: 512, height: 512, fit: 'inside', withoutEnlargement: true })
    .greyscale()
    .raw()
    .toBuffer({ resolveWithObject: true });

  const { width, height } = info;
  if (width < 3 || height < 3) return 0;

  let sum = 0;
  let sumSq = 0;
  let count = 0;
  for (let y = 1; y < height - 1; y += 1) {
    for (let x = 1; x < width - 1; x += 1) {
      const i = y * width + x;
      const value = -4 * data[i] + data[i - 1] + data[i + 1] + data[i - width] + data[i + width];
      sum += value;
      sumSq += value * value;
      count += 1;
    }
  }
  const mean = sum / count;
  return sumSq / count - mean * mean;
}
